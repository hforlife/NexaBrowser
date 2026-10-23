package com.nexa.nexa_browser.download

import android.app.Notification
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.SystemClock
import android.util.Log
import java.io.File
import java.net.HttpURLConnection
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

/**
 * Moteur des téléchargements : file d'attente (2 simultanés), pause / reprise,
 * nouvelles tentatives automatiques, reprise au retour du réseau, publication.
 *
 * Indépendant de l'interface Flutter : il continue quand l'app est fermée,
 * le processus étant maintenu par [DownloadForegroundService].
 * Tout l'état est protégé par [lock].
 */
object DownloadEngine {
    private const val TAG = "NexaDownloads"
    private const val MAX_CONCURRENT = 2

    /** Délais entre les tentatives successives (coupures 3G fréquentes). */
    private val RETRY_DELAYS_SECONDS: LongArray = longArrayOf(5, 15, 30, 60, 120)

    /** Fréquence max des mises à jour envoyées à l'interface, à la base et aux notifications. */
    private const val EVENT_INTERVAL_MS = 400L
    private const val PERSIST_INTERVAL_MS = 2_000L
    private const val NOTIFY_INTERVAL_MS = 1_000L

    private const val PARTIAL_DIRECTORY = "partial"
    private const val MP4_EXTENSION = "mp4"
    private const val TS_EXTENSION = "ts"
    private const val MIME_MP4 = "video/mp4"
    private const val MIME_TS = "video/mp2t"

    /** Clé de l'événement envoyé à Dart quand une tâche est supprimée. */
    const val KEY_REMOVED = "removed"

    private val lock = Any()
    private lateinit var appContext: Context
    private lateinit var store: DownloadStore
    private lateinit var notifier: DownloadNotifier
    private lateinit var publisher: DownloadPublisher
    private lateinit var fileDownloader: FileDownloader
    private lateinit var hlsDownloader: HlsDownloader

    private val tasks: LinkedHashMap<String, DownloadTask> = LinkedHashMap()
    private val jobs: HashMap<String, Job> = HashMap()
    private val listeners: CopyOnWriteArrayList<(Map<String, Any?>) -> Unit> = CopyOnWriteArrayList()

    private val workers: ExecutorService = Executors.newCachedThreadPool { runnable ->
        Thread(runnable, "nexa-download").apply { isDaemon = true }
    }
    private val scheduler: ScheduledExecutorService = Executors.newSingleThreadScheduledExecutor { runnable ->
        Thread(runnable, "nexa-download-retry").apply { isDaemon = true }
    }

    @Volatile
    private var initialized = false

    // ------------------------------------------------------------------ cycle de vie

    /** Charge les téléchargements enregistrés et relance ceux qui étaient en cours. Idempotent. */
    fun init(context: Context) {
        if (initialized) return
        synchronized(lock) {
            if (initialized) return
            appContext = context.applicationContext
            store = DownloadStore(appContext)
            notifier = DownloadNotifier(appContext)
            publisher = DownloadPublisher(appContext)
            val headers = RequestHeaders(appContext)
            fileDownloader = FileDownloader(headers)
            hlsDownloader = HlsDownloader(headers)
            for (task in store.all()) {
                // Interrompus par l'arrêt du processus : ils reprennent d'eux-mêmes
                if (task.status == DownloadStatus.RUNNING || task.status == DownloadStatus.CONVERTING ||
                    task.status == DownloadStatus.RETRYING
                ) {
                    task.status = DownloadStatus.QUEUED
                    store.save(task)
                }
                tasks[task.id] = task
            }
            initialized = true
        }
        registerNetworkCallback()
        pump()
    }

    fun addListener(listener: (Map<String, Any?>) -> Unit) = listeners.add(listener)

    fun removeListener(listener: (Map<String, Any?>) -> Unit) = listeners.remove(listener)

    // ------------------------------------------------------------------ commandes

    /** Tous les téléchargements, du plus récent au plus ancien. */
    fun list(): List<Map<String, Any?>> = synchronized(lock) {
        tasks.values.sortedByDescending { it.createdAt }.map { it.toWireMap() }
    }

    fun enqueue(
        url: String,
        fileName: String,
        mimeType: String?,
        referer: String?,
        isHls: Boolean,
        withCookies: Boolean,
    ): Map<String, Any?> {
        val task = DownloadTask(
            id = UUID.randomUUID().toString(),
            url = url,
            fileName = FileNames.sanitize(fileName),
            mimeType = mimeType,
            referer = referer,
            withCookies = withCookies,
            isHls = isHls,
            createdAt = System.currentTimeMillis(),
        )
        val wire: Map<String, Any?> = synchronized(lock) {
            tasks[task.id] = task
            store.save(task)
            task.toWireMap()
        }
        changed(task)
        pump()
        return wire
    }

    fun pause(id: String) {
        val task: DownloadTask = synchronized(lock) {
            val task: DownloadTask = tasks[id] ?: return
            if (!task.status.isPausable) return
            task.status = DownloadStatus.PAUSED
            task.error = null
            jobs[id]?.cancel()
            store.save(task)
            task
        }
        changed(task)
    }

    /** Met tout en pause (ex. : limite de durée du service atteinte sur Android 15). */
    fun pauseAll() {
        val ids: List<String> = synchronized(lock) {
            tasks.values.filter { it.status.isPausable }.map { it.id }
        }
        ids.forEach(::pause)
    }

    fun resume(id: String) {
        val task: DownloadTask = synchronized(lock) {
            val task: DownloadTask = tasks[id] ?: return
            if (task.status != DownloadStatus.PAUSED && task.status != DownloadStatus.FAILED) return
            task.status = DownloadStatus.QUEUED
            task.error = null
            task.retryCount = 0
            store.save(task)
            task
        }
        changed(task)
        pump()
    }

    /**
     * Retire le téléchargement de la liste ; [deleteFile] supprime aussi le fichier terminé.
     * Retourne faux si le fichier n'a pas pu être supprimé.
     */
    fun remove(id: String, deleteFile: Boolean): Boolean {
        val task: DownloadTask
        val wasRunning: Boolean
        synchronized(lock) {
            task = tasks.remove(id) ?: return true
            store.delete(id)
            val job: Job? = jobs[id]
            wasRunning = job != null
            job?.removed = true
            job?.cancel()
        }
        notifier.cancel(task)
        // Un transfert en cours nettoie ses fichiers lui-même en s'arrêtant
        if (!wasRunning) deletePartials(task)
        val fileDeleted: Boolean =
            if (deleteFile && task.status == DownloadStatus.COMPLETED) publisher.delete(task) else true
        emit(mapOf("id" to id, KEY_REMOVED to true))
        updateForeground()
        pump()
        return fileDeleted
    }

    /** Ouvre un fichier terminé dans l'app adaptée. */
    fun open(id: String): Boolean {
        val task: DownloadTask = synchronized(lock) { tasks[id]?.copy() } ?: return false
        return task.status == DownloadStatus.COMPLETED && publisher.open(task)
    }

    fun hasActiveTasks(): Boolean = synchronized(lock) { tasks.values.any { it.status.isActive } }

    fun foregroundNotification(): Notification = notifier.foreground(activeSnapshots())

    // ------------------------------------------------------------------ file d'attente

    /** Démarre les tâches en attente dans la limite de [MAX_CONCURRENT]. */
    private fun pump() {
        val started: MutableList<Job> = mutableListOf()
        synchronized(lock) {
            if (!initialized) return
            // Une tâche dont l'ancien transfert se termine encore n'est pas relancée tout de suite
            val waiting: List<DownloadTask> = tasks.values
                .filter { it.status == DownloadStatus.QUEUED && it.id !in jobs }
                .sortedBy { it.createdAt }
            for (task in waiting) {
                if (jobs.size >= MAX_CONCURRENT) break
                task.status = DownloadStatus.RUNNING
                task.error = null
                store.save(task)
                val job = Job(task)
                jobs[task.id] = job
                started += job
            }
        }
        started.forEach { job ->
            changed(job.task)
            workers.execute { run(job) }
        }
        updateForeground()
    }

    /** Résultat d'un transfert. */
    private sealed interface Outcome {
        object Cancelled : Outcome
        class Done(val published: DownloadPublisher.Published, val mimeType: String?) : Outcome
        class Failed(val error: DownloadException) : Outcome
    }

    /** Exécuté sur un thread de travail. */
    private fun run(job: Job) {
        val outcome: Outcome = try {
            if (job.task.isHls) runHls(job) else runFile(job)
        } catch (error: Throwable) {
            if (job.cancelled) Outcome.Cancelled else Outcome.Failed(DownloadErrors.from(error))
        }
        finish(job, outcome)
    }

    private fun runFile(job: Job): Outcome {
        val task: DownloadTask = job.task
        val partial = File(partialDirectory(), "${task.id}.part")
        fileDownloader.download(task, partial, job)
        if (job.cancelled) return Outcome.Cancelled
        val (fileName: String, mimeType: String?) = synchronized(lock) { task.fileName to task.mimeType }
        return Outcome.Done(publisher.publish(partial, fileName, mimeType), mimeType)
    }

    private fun runHls(job: Job): Outcome {
        val task: DownloadTask = job.task
        val directory: File = partialDirectory()
        val result: HlsDownloader.Result = hlsDownloader.download(task, directory, job) ?: return Outcome.Cancelled
        if (job.cancelled) return Outcome.Cancelled
        setStatus(job, DownloadStatus.CONVERTING)

        val baseName: String = synchronized(lock) { task.fileName }
        val converted = File(directory, "${task.id}.$MP4_EXTENSION.part")
        // (fichier à publier, nom, type MIME)
        val (source: File, fileName: String, mimeType: String) = try {
            if (!MediaRemuxer.remuxToMp4(result.trackFiles, converted) { job.cancelled }) return Outcome.Cancelled
            Triple(converted, FileNames.withExtension(baseName, MP4_EXTENSION), MIME_MP4)
        } catch (error: Exception) {
            converted.delete()
            if (result.trackFiles.size != 1) {
                throw DownloadException("Conversion en MP4 impossible (audio séparé)", false, error)
            }
            // Repli : fichier brut, lisible par VLC ou MX Player
            Log.w(TAG, "Conversion en MP4 impossible, fichier brut conservé", error)
            Triple(
                result.trackFiles.first(),
                FileNames.withExtension(baseName, if (result.isFragmentedMp4) MP4_EXTENSION else TS_EXTENSION),
                if (result.isFragmentedMp4) MIME_MP4 else MIME_TS,
            )
        }
        if (job.cancelled) return Outcome.Cancelled
        val published: DownloadPublisher.Published = publisher.publish(source, fileName, mimeType)
        // Les fichiers bruts ne sont supprimés qu'après publication réussie (reprise possible sinon)
        result.trackFiles.forEach(File::delete)
        return Outcome.Done(published, mimeType)
    }

    /** Fin d'un transfert : statut final, nouvel essai éventuel, tâche suivante. */
    private fun finish(job: Job, outcome: Outcome) {
        val task: DownloadTask = job.task
        synchronized(lock) {
            jobs.remove(task.id)
            if (!job.removed) {
                when (outcome) {
                    is Outcome.Done -> {
                        task.status = DownloadStatus.COMPLETED
                        task.fileName = outcome.published.fileName
                        task.mimeType = outcome.mimeType ?: task.mimeType
                        task.contentUri = outcome.published.contentUri
                        task.filePath = outcome.published.filePath
                        task.displayPath = outcome.published.displayPath
                        task.error = null
                        task.retryCount = 0
                    }
                    // Le statut a déjà été fixé par pause() ou resume()
                    is Outcome.Cancelled -> Unit
                    is Outcome.Failed -> applyFailure(task, outcome.error)
                }
                store.save(task)
            }
        }
        if (job.removed) deletePartials(task) else changed(task)
        pump()
    }

    /** Erreur : attente du réseau, nouvel essai différé, ou échec définitif. */
    private fun applyFailure(task: DownloadTask, error: DownloadException) {
        task.error = error.message
        when {
            !error.retryable -> task.status = DownloadStatus.FAILED
            !isNetworkAvailable() -> task.status = DownloadStatus.WAITING_NETWORK
            task.retryCount < RETRY_DELAYS_SECONDS.size -> {
                val delay: Long = RETRY_DELAYS_SECONDS[task.retryCount]
                task.retryCount++
                task.status = DownloadStatus.RETRYING
                scheduler.schedule({ retryNow(task.id) }, delay, TimeUnit.SECONDS)
            }
            else -> task.status = DownloadStatus.FAILED
        }
    }

    private fun retryNow(id: String) {
        val task: DownloadTask = synchronized(lock) {
            val task: DownloadTask = tasks[id] ?: return
            if (task.status != DownloadStatus.RETRYING) return
            task.status = DownloadStatus.QUEUED
            store.save(task)
            task
        }
        changed(task)
        pump()
    }

    private fun setStatus(job: Job, status: DownloadStatus) {
        synchronized(lock) {
            if (job.cancelled) return
            job.task.status = status
            store.save(job.task)
        }
        changed(job.task)
    }

    // ------------------------------------------------------------------ réseau

    private fun registerNetworkCallback() {
        val manager: ConnectivityManager = appContext.getSystemService(ConnectivityManager::class.java) ?: return
        try {
            manager.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) = onNetworkAvailable()
            })
        } catch (error: RuntimeException) {
            Log.w(TAG, "Surveillance du réseau impossible", error)
        }
    }

    /** Le réseau revient : les téléchargements en attente repartent. */
    private fun onNetworkAvailable() {
        val resumed: List<DownloadTask> = synchronized(lock) {
            tasks.values.filter { it.status == DownloadStatus.WAITING_NETWORK }.onEach {
                it.status = DownloadStatus.QUEUED
                it.error = null
                store.save(it)
            }
        }
        if (resumed.isEmpty()) return
        resumed.forEach(::changed)
        pump()
    }

    private fun isNetworkAvailable(): Boolean {
        val manager: ConnectivityManager = appContext.getSystemService(ConnectivityManager::class.java) ?: return true
        val capabilities: NetworkCapabilities = manager.getNetworkCapabilities(manager.activeNetwork) ?: return false
        return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }

    // ------------------------------------------------------------------ diffusion

    /** Prévient l'interface, met à jour la notification et le service au premier plan. */
    private fun changed(task: DownloadTask) {
        val snapshot: DownloadTask = synchronized(lock) {
            if (!tasks.containsKey(task.id)) return
            task.copy()
        }
        emit(snapshot.toWireMap())
        when (snapshot.status) {
            DownloadStatus.COMPLETED -> notifier.completed(snapshot, publisher.openIntent(snapshot))
            DownloadStatus.FAILED -> notifier.failed(snapshot)
            else -> notifier.progress(snapshot)
        }
        updateForeground()
    }

    /** Progression d'un transfert, avec limitation de fréquence. */
    private fun progress(job: Job, mutate: (DownloadTask) -> Unit) {
        val now: Long = SystemClock.elapsedRealtime()
        var snapshot: DownloadTask? = null
        var notify = false
        synchronized(lock) {
            if (job.cancelled) return
            mutate(job.task)
            if (now - job.lastPersistAt >= PERSIST_INTERVAL_MS) {
                job.lastPersistAt = now
                store.save(job.task)
            }
            if (now - job.lastEventAt >= EVENT_INTERVAL_MS) {
                job.lastEventAt = now
                snapshot = job.task.copy()
            }
            if (now - job.lastNotifyAt >= NOTIFY_INTERVAL_MS) {
                job.lastNotifyAt = now
                notify = true
                if (snapshot == null) snapshot = job.task.copy()
            }
        }
        val current: DownloadTask = snapshot ?: return
        emit(current.toWireMap())
        if (notify) notifier.progress(current)
    }

    private fun emit(event: Map<String, Any?>) = listeners.forEach { it(event) }

    private fun activeSnapshots(): List<DownloadTask> = synchronized(lock) {
        tasks.values.filter { it.status.isActive }.map { it.copy() }
    }

    private fun updateForeground() {
        val active: List<DownloadTask> = activeSnapshots()
        if (active.isEmpty()) {
            DownloadForegroundService.stop()
            notifier.cancelForeground()
        } else {
            DownloadForegroundService.ensureStarted(appContext)
            notifier.updateForeground(active)
        }
    }

    // ------------------------------------------------------------------ fichiers

    /** Fichiers en cours d'écriture : dossier propre à l'app, invisible des autres apps. */
    private fun partialDirectory(): File =
        File(appContext.getExternalFilesDir(null) ?: appContext.filesDir, PARTIAL_DIRECTORY).apply { mkdirs() }

    private fun deletePartials(task: DownloadTask) {
        partialDirectory().listFiles { file -> file.name.startsWith("${task.id}.") }?.forEach(File::delete)
    }

    // ------------------------------------------------------------------ transfert

    /** Un transfert en cours : annulation et remontée de progression. */
    private class Job(val task: DownloadTask) : TransferContext {
        @Volatile
        var cancelled = false

        @Volatile
        var removed = false

        @Volatile
        private var connection: HttpURLConnection? = null

        // Accédés sous le verrou du moteur
        var lastEventAt = 0L
        var lastPersistAt = 0L
        var lastNotifyAt = 0L
        private var firstReceived: Long = -1L

        override val isCancelled: Boolean get() = cancelled

        /** Annule et coupe la connexion (hors du thread principal : la fermeture TLS fait du réseau). */
        fun cancel() {
            cancelled = true
            connection?.let(::disconnectInBackground)
        }

        override fun attach(connection: HttpURLConnection?) {
            this.connection = connection
            if (connection != null && cancelled) disconnectInBackground(connection)
        }

        override fun onFileProgress(receivedBytes: Long, totalBytes: Long?) = progress(this) { task ->
            task.receivedBytes = receivedBytes
            task.totalBytes = totalBytes
            resetRetriesIfAdvancing(task, receivedBytes)
        }

        override fun onValidators(etag: String?, lastModified: String?) = progress(this) { task ->
            task.etag = etag
            task.lastModified = lastModified
        }

        override fun onMimeType(mimeType: String?) = progress(this) { task ->
            if (task.mimeType.isNullOrBlank() && !mimeType.isNullOrBlank()) task.mimeType = mimeType
        }

        override fun onSegmentProgress(segmentsDone: Int, segmentsTotal: Int, receivedBytes: Long, resumeOffset: Long) =
            progress(this) { task ->
                task.segmentsDone = segmentsDone
                task.segmentsTotal = segmentsTotal
                task.receivedBytes = receivedBytes
                task.resumeOffset = resumeOffset
                resetRetriesIfAdvancing(task, receivedBytes)
            }

        override fun onEstimatedSize(totalBytes: Long?) = progress(this) { task -> task.totalBytes = totalBytes }

        /** Des données arrivent à nouveau : le compteur d'essais repart de zéro. */
        private fun resetRetriesIfAdvancing(task: DownloadTask, receivedBytes: Long) {
            if (firstReceived < 0) {
                firstReceived = receivedBytes
            } else if (receivedBytes > firstReceived) {
                task.retryCount = 0
            }
        }

        private fun disconnectInBackground(connection: HttpURLConnection) {
            workers.execute {
                try {
                    connection.disconnect()
                } catch (error: RuntimeException) {
                    // Connexion déjà fermée
                }
            }
        }
    }
}
