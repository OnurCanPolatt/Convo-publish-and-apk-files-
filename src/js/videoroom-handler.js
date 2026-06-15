    // Optimized VideoRoom Handler - Fixed Video Layout with Robust Media Management
    let globalJanusServerUrl = null;

    let janus = null;
    let videoroom = null;
    let myId = null;
    let currentRoom = null;
    let isPublishing = false;
    let subscribers = {};
    let isSwapped = false;
    
    // Global media management
    let currentLocalStream = null;
    let mediaRequestInProgress = false;
    
    // Helper Functions
    function subscribeToPublisher(publisherId, displayName) {
        console.log('🔌 CREATING SUBSCRIBER FOR:', publisherId);
        let remoteFeed = null;
        let remoteStream = new MediaStream();
    
        janus.attach({
            plugin: "janus.plugin.videoroom",
            success: function (pluginHandle) {
                remoteFeed = pluginHandle;
                subscribers[publisherId] = remoteFeed;
    
                remoteFeed.send({
                    message: {
                        request: 'join',
                        room: currentRoom,
                        ptype: 'subscriber',
                        feed: publisherId
                    }
                });
            },
            error: function (error) {
                console.error('❌ SUBSCRIBER ATTACH ERROR:', error);
            },
            onmessage: function (msg, jsep) {
                if (jsep) {
                    remoteFeed.createAnswer({
                        jsep: jsep,
                        media: { audioSend: false, videoSend: false, audioRecv: true, videoRecv: true, data: false },
                        success: function (jsep) {
                            remoteFeed.send({
                                message: { request: 'start', room: currentRoom },
                                jsep: jsep
                            });
                        },
                        error: function (error) {
                            console.error('❌ CREATE ANSWER ERROR:', error);
                        }
                    });
                }
            },
            onremotetrack: function (track, mid, added) {
                if (added) {
                    remoteStream.addTrack(track);
                    const elementId = 'remote-' + publisherId;

                    // 1. Olay Dinleyicileri (Event Listeners)
                    // Bazı tarayıcılar track durduğunda bu event'i fırlatır.
                    track.onmute = (event) => {
                        console.log("🔇 Track Muted (Event):", publisherId, event);
                        document.getElementById(elementId)?.classList.add('video-muted');
                    };

                    track.onunmute = (event) => {
                        console.log("🔊 Track Unmuted (Event):", publisherId, event);
                        document.getElementById(elementId)?.classList.remove('video-muted');
                    };

                    // 2. Video Akış Kontrolü (Watchdog) - EN ÖNEMLİ KISIM
                    // 'mute' eventi tetiklenmese bile görüntünün donup donmadığını anlarız.
                    if (track.kind === 'video') {
                        let lastCheckTime = -1;
                        let freezeCounter = 0;

                        // Bu interval, abone (subscriber) handle'ı canlı olduğu sürece çalışır
                        const videoWatchdog = setInterval(() => {
                            const container = document.getElementById(elementId);
                            const videoElement = container ? container.querySelector('video') : null;

                            // Eğer element silindiyse interval'i temizle
                            if (!container) {
                                clearInterval(videoWatchdog);
                                return;
                            }

                            if (videoElement && !videoElement.paused) {
                                const currentTime = videoElement.currentTime;

                                // Eğer video zamanı ilerlemiyorsa (donmuşsa)
                                if (currentTime === lastCheckTime) {
                                    freezeCounter++;
                                    // 2 saniye (2 kontrol) boyunca donmuşsa siyah ekranı göster
                                    if (freezeCounter >= 2) {
                                        if (!container.classList.contains('video-muted')) {
                                            console.log("❄️ Video donması algılandı, karartılıyor:", publisherId);
                                            container.classList.add('video-muted');
                                        }
                                    }
                                } else {
                                    // Video akıyor
                                    freezeCounter = 0;
                                    if (container.classList.contains('video-muted')) {
                                        console.log("▶️ Video akışı geri geldi:", publisherId);
                                        container.classList.remove('video-muted');
                                    }
                                }
                                lastCheckTime = currentTime;
                            }
                        }, 1000); // Saniyede bir kontrol et
                    }

                    // 3. Video Elementini Oluştur (Eğer yoksa)
                    if (!document.getElementById(elementId)) {
                        // remoteStream zaten tüm trackleri (ses+video) içerir
                        addVideo(remoteStream, displayName || 'Remote', false, publisherId);

                        // Remote-connected class ekle (UI yerleşimi için)
                        document.querySelector('#chat-panel-section')?.classList.add('remote-connected');
                    } else {
                        // Eğer element zaten varsa sadece srcObject güncelle (Yeni track gelmiş olabilir)
                        const v = document.querySelector(`#${elementId} video`);
                        if (v) v.srcObject = remoteStream;
                    }
                }
            },
            oncleanup: function () {
                removeVideo('remote-' + publisherId);
                delete subscribers[publisherId];

                // ✅ Swap durumunu sıfırla
                if (isSwapped) {
                    isSwapped = false;
                }

                // DÜZELTME: Remote video kalmadıysa body class'ını kaldır
                const remainingRemoteVideos = document.querySelectorAll('.chat .video-box.remote-video');
                if (remainingRemoteVideos.length === 0) {
                    document.querySelector('#chat-panel-section')?.classList.remove('remote-connected');
                    console.log('🔄 Remote disconnected - returned to solo mode');
                }
            }
        });
    }
    
    function startPublishing() {
        if (isPublishing || document.getElementById('local-video')) {
            console.log('⚠️ Zaten yayın yapılıyor');
            return;
        }
    
        if (mediaRequestInProgress) {
            console.log('Medya talebi zaten devam ediyor');
            return;
        }
    
        console.log('🎥 Medya erişimi isteniyor...');
        mediaRequestInProgress = true;
    
        // Önce mevcut stream'i temizle
        if (currentLocalStream) {
            currentLocalStream.getTracks().forEach(track => track.stop());
            currentLocalStream = null;
        }
    
        // Retry mekanizması ile getUserMedia
        attemptMediaAccess(3);
    }

    function attemptMediaAccess(attemptsLeft) {
        if (attemptsLeft <= 0) {
            console.error('Medya erişimi başarısız - tüm denemeler tükendi');
            showToast('Medya erişimi başarısız. Sayfayı yenileyin.', 'error');
            mediaRequestInProgress = false;
            return;
        }

        console.log(`Medya erişimi denemesi: ${4 - attemptsLeft}/3`);

        const timeoutPromise = new Promise((_, reject) => {
            setTimeout(() => reject(new Error('timeout')), 5000);
        });

        const mediaPromise = navigator.mediaDevices.getUserMedia({
            video: {
                width: { ideal: 640 },
                height: { ideal: 480 },
                frameRate: { ideal: 15 }
            },
            audio: {
                echoCancellation: true,
                noiseSuppression: true
            }
        });

        Promise.race([mediaPromise, timeoutPromise])
            .then(function (stream) {
                console.log('✅ Medya erişimi başarılı');
                currentLocalStream = stream;
                mediaRequestInProgress = false;

                addVideo(stream, 'Sen', true);
                isPublishing = true;

                // --- YENİ MANTIK BURADA BAŞLIYOR ---

                // 1. Başlangıçta sesi bilerek kapalı yayınla
                stream.getAudioTracks().forEach(track => track.enabled = false);

                videoroom.createOffer({
                    media: { audioSend: true, videoSend: true, audioRecv: false, videoRecv: false },
                    stream: stream,
                    success: function (jsep) {
                        // 2. Janus'a da sesin kapalı olduğunu bildir
                        videoroom.send({
                            message: { request: 'configure', audio: false, video: true },
                            jsep: jsep
                        });
                        console.log('🎤 Local audio/video publishing started (audio initially muted).');

                        // 3. Çok kısa bir süre sonra sesi otomatik olarak aç
                        setTimeout(() => {
                            console.log('🔊 Automatically enabling microphone...');
                            window.toggleMicrophone(); // Düzeltilmiş, hafif toggle fonksiyonumuzu çağırıyoruz
                        }, 500); // Yarım saniye bekle
                    },
                    error: function (error) {
                        console.error('❌ CREATE OFFER ERROR:', error);
                    }
                });
            })
            .catch(function (error) {
                // ... hata yönetimi kodun aynı kalabilir ...
                console.error("----------- HATA DETAYI -----------");
                console.error("GERÇEK HATA NESNESİ:", error);
                console.error("HATANIN ADI (En Önemlisi):", error.name);
                console.error("HATANIN MESAJI:", error.message);
                console.error("---------------------------------");
                console.log(`Deneme başarısız: ${error.name}, Kalan: ${attemptsLeft - 1}`);

                if (error.message === 'timeout' || error.name === 'AbortError') {
                    setTimeout(() => attemptMediaAccess(attemptsLeft - 1), 1000);
                } else {
                    attemptMediaAccess(attemptsLeft - 1);
                }
            });
    }
    
    function cleanupSubscriber(publisherId) {
        if (subscribers[publisherId]) {
            subscribers[publisherId].detach();
            delete subscribers[publisherId];
        }
    }

    function addVideo(stream, label, isLocal, publisherId = null) {
        const elementId = isLocal ? 'local-video' : 'remote-' + publisherId;

        if (document.getElementById(elementId)) {
            console.log('⚠️ Video zaten var:', elementId);
            return;
        }

        const videoBox = document.createElement('div');
        videoBox.className = 'video-box';
        videoBox.id = elementId;

        const video = document.createElement('video');
        video.srcObject = stream;
        video.autoplay = true;
        video.playsInline = true;
        video.muted = isLocal;

        const videoLabel = document.createElement('div');
        videoLabel.className = 'video-label';
        videoLabel.textContent = label;

        videoBox.appendChild(video);
        videoBox.appendChild(videoLabel);

        // ✅ YENİ: Remote video geldiğinde nereye ekleyeceğine karar ver
        if (!isLocal) {
            const backgroundContainer = document.getElementById('background-video');
            const smallContainer = document.getElementById('small-videos');

            // Eğer arka planda video yoksa, bu video arka plana gitsin
            if (backgroundContainer.children.length === 0) {
                backgroundContainer.appendChild(videoBox);
                console.log('✅ İlk remote video arka plana eklendi');
            } else {
                // Eski arka plan videosunu küçültüp üste taşı
                const oldBg = backgroundContainer.firstChild;
                if (oldBg) {
                    backgroundContainer.removeChild(oldBg);
                    smallContainer.appendChild(oldBg);
                    console.log('✅ Eski video küçük videolara taşındı');
                }
                // Yeni videoyu arka plana ekle
                backgroundContainer.appendChild(videoBox);
                console.log('✅ Yeni video arka plana eklendi');
            }
        } else {
            // Local video her zaman küçük videolara
            document.getElementById('small-videos').appendChild(videoBox);
            console.log('✅ Local video küçük videolara eklendi');
        }

        // Click event - swap için
        videoBox.addEventListener('click', function() {
            const backgroundContainer = document.getElementById('background-video');
            const smallContainer = document.getElementById('small-videos');
            const currentBg = backgroundContainer.firstChild;

            if (currentBg === videoBox) {
                // Arka plan videoya tıklandı - hiçbir şey yapma
                return;
            }

            // Videoları swap et
            if (currentBg) {
                backgroundContainer.removeChild(currentBg);
                smallContainer.appendChild(currentBg);
            }

            if (videoBox.parentNode === smallContainer) {
                smallContainer.removeChild(videoBox);
                backgroundContainer.appendChild(videoBox);
            }

            console.log('✅ Video swap edildi');
        });

        video.play().catch(e => console.log('Video play error:', e));
    }
    
    // ✅ YENİ: Tüm videolar için ortak click handler
    function handleVideoClick(clickedVideoBox) {
        // Swapped olan varsa temizle
        const currentSwapped = document.querySelector('.chat .video-box.swapped');

        if (currentSwapped === clickedVideoBox) {
            // Aynı videoya tekrar tıklandı, swap'i kaldır
            clickedVideoBox.classList.remove('swapped');
            isSwapped = false;
            console.log('✅ Swap kaldırıldı');
        } else {
            // Farklı videoya tıklandı veya ilk swap
            if (currentSwapped) {
                currentSwapped.classList.remove('swapped');
            }
            clickedVideoBox.classList.add('swapped');
            isSwapped = true;
            console.log('✅ Video swap edildi:', clickedVideoBox.id);
        }
    }
    
    function removeVideo(elementId) {
        const element = document.getElementById(elementId);
        if (element) {
            const video = element.querySelector('video');
            if (video && video.srcObject) {
                video.srcObject.getTracks().forEach(track => {
                    track.stop();
                    console.log('Track stopped:', track.kind);
                });
                video.srcObject = null;
            }
            element.remove();
            console.log('✅ Video removed:', elementId);
        }
    }
    
    // Main Functions
    window.initJanus = function (serverUrl) { // <-- DÜZELTME 1
        if (serverUrl) {
            globalJanusServerUrl = serverUrl; // Adresi hafızaya al
        }
        return new Promise((resolve, reject) => {
            Janus.init({
                debug: true,
                callback: function () {
                    janus = new Janus({
                        server: serverUrl, // <-- DÜZELTME 2
                        iceServers: [
                            { urls: "stun:stun.l.google.com:19302" },
                            { urls: "stun:stun1.l.google.com:19302" }
                        ],
                        iceTransportPolicy: "all",
                        success: function () {
                            console.log('✅ Janus connected successfully to:', serverUrl);

                            janus.attach({
                                plugin: "janus.plugin.videoroom",
                                success: function (pluginHandle) {
                                    videoroom = pluginHandle;
                                    window.videoroom = pluginHandle; // ✅ Global ekle
                                    window.currentRoom = currentRoom; // ✅ Global ekle
                                    console.log('✅ VideoRoom plugin attached');
                                    console.log('✅ Global videoroom set:', !!window.videoroom);
                                    resolve(true);
                                },


                                error: reject,
                                onmessage: function (msg, jsep) {
                                    console.log('📨 VideoRoom message:', msg);
                                    if (msg.configured === "ok") {
                                        // Bu mesaj yayıncı kamerasını kapattığında abonelere (subscriber) de ulaşabilir
                                        // Janus sürümüne göre 'videoroom': 'event' içinde 'substream' veya 'talking' bilgisi döner.
                                    }
                                    if (msg.videoroom === 'joined') {
                                        myId = msg.id;
                                        currentRoom = msg.room;
                                        console.log('✅ Joined room:', currentRoom, 'with ID:', myId);

                                        if (msg.publishers) {
                                            msg.publishers.forEach(p => {
                                                if (p.id !== myId) {
                                                    console.log('📡 Subscribing to existing publisher:', p.id);
                                                    subscribeToPublisher(p.id, p.display);
                                                }
                                            });
                                        }
                                        startPublishing();
                                    } else if (msg.videoroom === 'event') {
                                        if (msg.publishers) {
                                            msg.publishers.forEach(p => {
                                                if (p.id !== myId) {
                                                    console.log('📡 New publisher joined:', p.id);
                                                    subscribeToPublisher(p.id, p.display);
                                                }
                                            });
                                        }
                                        if (msg.leaving) {
                                            console.log('🚪 Publisher leaving:', msg.leaving);
                                            removeVideo('remote-' + msg.leaving);
                                            cleanupSubscriber(msg.leaving);
                                        }
                                        if (msg.unpublished) {
                                            console.log('📴 Publisher unpublished:', msg.unpublished);
                                            removeVideo('remote-' + msg.unpublished);
                                            cleanupSubscriber(msg.unpublished);
                                        }
                                    }
                                    if (jsep) {
                                        videoroom.handleRemoteJsep({ jsep: jsep });
                                    }
                                }
                            });
                        },
                        error: function (error) { // Janus nesnesi oluşturulurken hata olursa
                            console.error("Janus object creation error:", error);
                            reject(error);
                        }
                    });
                },
                error: function (error) { // Janus.init'te hata olursa
                    console.error("Janus.init error:", error);
                    reject(error);
                }
            });
        });
    };
    
    window.createRoom = function (roomId,displayName) {
        return new Promise(async (resolve) => {
            isSwapped = false;
            mediaRequestInProgress = false;
            document.body.classList.remove('remote-connected'); // Reset
    
            if (!janus || !videoroom || janus.isConnected() === false) {
                try {
                    await initJanus(globalJanusServerUrl);
                    await new Promise(r => setTimeout(r, 3000));
                } catch (error) {
                    console.error('Janus init error:', error);
                    showToast('Janus bağlantısı kurulamadı!', 'error');
                    resolve(false);
                    return;
                }
            }
    
            if (!videoroom) {
                showToast('VideoRoom bağlantısı yok!', 'error');
                resolve(false);
                return;
            }
    
            videoroom.send({
                message: {
                    request: 'create',
                    room: roomId,
                    publishers: 10,
                    permanent: false,
                    audio_codec: 'opus',
                    video_codec: 'vp8'
                },
                success: function () {
                    console.log('✅ Room created:', roomId);
                    showToast('Konferans odası oluşturuldu!', 'success');
                    joinRoom(roomId,displayName).then(resolve);
                },
                error: function (error) {
                    console.error('❌ Room create error:', error);
                    showToast('Konferans odası oluşturulamadı!', 'error');
                    resolve(false);
                }
            });
        });
    };
    
    window.joinRoom = function (roomId,displayName) {
        return new Promise(async (resolve) => {
            isSwapped = false;
            mediaRequestInProgress = false;
            document.body.classList.remove('remote-connected'); // Reset
    
            if (!videoroom) {
                try {
                    await initJanus(globalJanusServerUrl);
                    await new Promise(r => setTimeout(r, 2000));
                } catch (error) {
                    console.error('Janus init error:', error);
                    resolve(false);
                    return;
                }
            }
    
            if (!videoroom) {
                resolve(false);
                return;
            }
    
            videoroom.send({
                message: {
                    request: 'join',
                    room: roomId,
                    ptype: 'publisher',
                    display: displayName || 'Misafir'
                },
                success: function () {
                    console.log('✅ Joined room:', roomId);
                    resolve(true);
                },
                error: function (error) {
                    console.error('❌ Room join error:', error);
                    showToast('Konferansa katılınamadı!', 'error');
                    resolve(false);
                }
            });
        });
    };

    // -------------------------
    // Ortak yardımcı fonksiyonlar
    // -------------------------

    function stopStream(stream) {
        if (!stream) return;
        stream.getTracks().forEach(track => {
            track.stop();
            console.log('Track stopped:', track.kind);
        });
    }

    function clearVideoElements() {
        // Her iki container'daki videoları temizle
        const selectors = ['#background-video video', '#small-videos video'];
        selectors.forEach(selector => {
            document.querySelectorAll(selector).forEach(video => {
                if (video.srcObject) {
                    stopStream(video.srcObject);
                    video.srcObject = null;
                }
                video.remove();
            });
        });
    }

    function cleanupAllSubscribers() {
        Object.keys(subscribers).forEach(publisherId => {
            if (typeof cleanupSubscriber === 'function') {
                cleanupSubscriber(publisherId);
            } else if (subscribers[publisherId]) {
                subscribers[publisherId].detach();
            }
            delete subscribers[publisherId];
        });
        subscribers = {};
    }

    function resetRoomState() {
        isSwapped = false;
        mediaRequestInProgress = false;
        myId = null;
        currentRoom = null;
        isPublishing = false;
        document.querySelector('#chat-panel-section')?.classList.remove('remote-connected');
    }

    // -------------------------
    // Odayı bırakma (medya temizleme)
    // -------------------------
    window.leaveRoomOnly = function () {
        console.error("!!! 'leaveRoomOnly' çağrıldı !!!");
        console.trace();

        // Local stream ve videoları temizle
        stopStream(currentLocalStream);
        currentLocalStream = null;
        clearVideoElements();

        // Subscribers temizle
        cleanupAllSubscribers();

        // Videoroom’dan çık
        if (videoroom && currentRoom) {
            if (isPublishing) {
                videoroom.send({ message: { request: 'unpublish' } });
            }
            videoroom.send({ message: { request: 'leave' } });
            videoroom.detach();
            videoroom = null;
        }

        resetRoomState();

        console.log('✅ Odayı bırakıldı ve medya temizlendi');
    };

    // -------------------------
    // Odayı ve kaynakları tamamen yok etme
    // -------------------------
    window.destroyAndLeaveRoom = function () {
        console.error("!!! 'destroyAndLeaveRoom' çağrıldı !!!");
        console.trace();

        stopStream(currentLocalStream);
        currentLocalStream = null;
        clearVideoElements();
        cleanupAllSubscribers();

        if (videoroom && currentRoom) {
            if (isPublishing) {
                videoroom.send({ message: { request: 'unpublish' } });
            }
            videoroom.send({ message: { request: 'leave' } });

            // ✅ DEĞİŞİKLİK: 'destroy' komutunu ÖNCE gönder.
            videoroom.send({
                message: { request: 'destroy', room: currentRoom, permanent: false },
                success: () => console.log('✅ Oda yok etme isteği gönderildi:', currentRoom),
                error: (err) => console.warn('⚠️ Oda yok etme isteği hatası:', err)
            });

            // ❌ ESKİ 'setTimeout' bloğu SİLİNDİ.

            // ✅ 'destroy' komutu gittikten SONRA eklentiyi ayır (detach).
            videoroom.detach();
            videoroom = null;
        }

        // ❌ 'janus.destroy()' hâlâ yorumda/silinmiş olmalı (Bu doğru)
        /*
        if (janus) {
            janus.destroy();
            janus = null;
        }
        */

        resetRoomState();
        console.log('✅ Oda yok edildi ve kaynaklar temizlendi (Janus bağlantısı AKTİF)');
    };
    
    // videohandler.js dosyanıza EKLEYİN

    window.getParticipantCount = function () {
        if (!videoroom) {
            // Eğer bir odaya bağlı değilsek, katılımcı sayısı 0'dır.
            console.warn("getParticipantCount: Not in a room.");
            return 0;
        }

        // 'subscribers' = bizim dışımızdaki diğer katılımcılar (remote feeds)
        const remoteCount = Object.keys(subscribers).length;

        // 'isPublishing' = biz (local feed)
        const selfCount = isPublishing ? 1 : 0;

        const totalCount = remoteCount + selfCount;

        console.log(`Participant count check: ${totalCount} (Self: ${selfCount}, Others: ${remoteCount})`);

        // Güvenilir toplam katılımcı sayısını C#'a döndür
        return totalCount;
    };

    window.toggleMicrophone = function () {
        const localVideo = document.querySelector('#local-video video');
        if (localVideo && localVideo.srcObject) {
            const audioTracks = localVideo.srcObject.getAudioTracks();
            if (audioTracks.length > 0) {
                const audioTrack = audioTracks[0];
                const newAudioState = !audioTrack.enabled;

                // Sadece track'in durumunu değiştir
                audioTrack.enabled = newAudioState;

                // Janus'a sadece durumu bildir, yeniden müzakere YOK!
                if (videoroom && isPublishing) {
                    videoroom.send({
                        message: {
                            request: 'configure',
                            audio: newAudioState
                        }
                    });
                    console.log('🎤 Microphone state configured:', newAudioState ? 'enabled' : 'disabled');
                }

                const micButton = document.querySelector('.btn-mic');
                if (micButton) {
                    micButton.classList.toggle('muted', !newAudioState);
                }

                console.log('🎤 Microphone:', newAudioState ? 'enabled' : 'disabled');
                showToast(newAudioState ? 'Mikrofon açıldı' : 'Mikrofon kapatıldı', 'info');
                return newAudioState;
            }
        }
        return false;
    };
    window.toggleCamera = function () {
        const localContainer = document.querySelector('#local-video'); // Ana kutu
        const localVideo = localContainer ? localContainer.querySelector('video') : null;

        if (localVideo && localVideo.srcObject) {
            const videoTracks = localVideo.srcObject.getVideoTracks();
            if (videoTracks.length > 0) {
                const videoTrack = videoTracks[0];
                const newVideoState = !videoTrack.enabled;

                videoTrack.enabled = newVideoState;

                // ✅ YENİ: Kendi kutumuza da karartma sınıfını ekle/çıkar
                if (!newVideoState) {
                    localContainer.classList.add('video-muted');
                } else {
                    localContainer.classList.remove('video-muted');
                }

                if (videoroom && isPublishing) {
                    videoroom.send({
                        message: { request: 'configure', video: newVideoState }
                    });
                }

                const cameraButton = document.querySelector('.btn-camera');
                if (cameraButton) {
                    cameraButton.classList.toggle('off', !newVideoState);
                }

                showToast(newVideoState ? 'Kamera açıldı' : 'Kamera kapatıldı', 'info');
                return newVideoState;
            }
        }
        return false;
    };
    
    window.showToast = (message, type) => {
        if (typeof Swal === 'undefined') {
            console.log(`${type.toUpperCase()}: ${message}`);
            return;
        }
    
        const Toast = Swal.mixin({
            toast: true,
            position: 'top-end',
            showConfirmButton: false,
            timer: 3000,
            timerProgressBar: true
        });
    
        Toast.fire({ icon: type, title: message });
    };
    
    // Global functions - Swap artık otomatik click ile çalışıyor