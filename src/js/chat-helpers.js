    // Mesajları otomatik scroll et
    window.scrollToBottom = (elementId) => {
        const element = document.getElementById(elementId);
        if (element) {
            element.scrollTop = element.scrollHeight;
        }
    };

    // CORS sorunu olmadan dosya indirme (hem local hem domain)
    window.downloadFile = (fileUrl, fileName) => {
        try {
            // <a> linki oluştur
            const a = document.createElement('a');
            a.href = fileUrl;
            a.download = fileName || '';
            a.target = '_blank'; // CORS’ta fetch yerine tarayıcı linki kullan
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);

            console.log(`Dosya indirildi: ${fileName}`);
        } catch (error) {
            console.error('Dosya indirme hatası:', error);
        }
    };

    
    // Progress bar ile dosya indirme (daha gelişmiş)
    window.downloadFileWithProgress = async (fileUrl, fileName, progressCallback) => {
        try {
            const response = await fetch(fileUrl);
    
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
    
            const contentLength = response.headers.get('content-length');
            const total = parseInt(contentLength, 10);
            let loaded = 0;
    
            const reader = response.body.getReader();
            const chunks = [];
    
            while (true) {
                const { done, value } = await reader.read();
    
                if (done) break;
    
                chunks.push(value);
                loaded += value.length;
    
                if (progressCallback && total) {
                    const progress = (loaded / total) * 100;
                    progressCallback(progress, loaded, total);
                }
            }
    
            // Chunks'ları birleştir
            const chunksAll = new Uint8Array(loaded);
            let position = 0;
            for (const chunk of chunks) {
                chunksAll.set(chunk, position);
                position += chunk.length;
            }
    
            // Blob oluştur ve indir
            const blob = new Blob([chunksAll]);
            const url = window.URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = fileName;
            a.click();
    
            window.URL.revokeObjectURL(url);
    
        } catch (error) {
            console.error('Dosya indirme hatası:', error);
            throw error;
        }
    };
    
    // Hata dialog göster
    window.showErrorDialog = (title, message) => {
        // Bootstrap modal varsa onu kullan, yoksa basit alert
        if (typeof bootstrap !== 'undefined' && bootstrap.Modal) {
            // Bootstrap modal kodu
            const modalHtml = `
                <div class="modal fade" id="errorModal" tabindex="-1">
                    <div class="modal-dialog">
                        <div class="modal-content">
                            <div class="modal-header">
                                <h5 class="modal-title">${title}</h5>
                                <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
                            </div>
                            <div class="modal-body">
                                <p>${message}</p>
                            </div>
                            <div class="modal-footer">
                                <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Tamam</button>
                            </div>
                        </div>
                    </div>
                </div>
            `;
    
            // Eski modal varsa kaldır
            const existingModal = document.getElementById('errorModal');
            if (existingModal) {
                existingModal.remove();
            }
    
            // Yeni modal ekle
            document.body.insertAdjacentHTML('beforeend', modalHtml);
            const modal = new bootstrap.Modal(document.getElementById('errorModal'));
            modal.show();
    
            // Modal kapandığında DOM'dan kaldır
            document.getElementById('errorModal').addEventListener('hidden.bs.modal', function () {
                this.remove();
            });
    
        } else {
            // Basit alert fallback
            alert(`${title}\n\n${message}`);
        }
    };
    
    // Başarı mesajı göster
    window.showSuccessDialog = (title, message) => {
        if (typeof bootstrap !== 'undefined' && bootstrap.Modal) {
            const modalHtml = `
                <div class="modal fade" id="successModal" tabindex="-1">
                    <div class="modal-dialog">
                        <div class="modal-content">
                            <div class="modal-header bg-success text-white">
                                <h5 class="modal-title">${title}</h5>
                                <button type="button" class="btn-close btn-close-white" data-bs-dismiss="modal"></button>
                            </div>
                            <div class="modal-body">
                                <p>${message}</p>
                            </div>
                            <div class="modal-footer">
                                <button type="button" class="btn btn-success" data-bs-dismiss="modal">Tamam</button>
                            </div>
                        </div>
                    </div>
                </div>
            `;
    
            const existingModal = document.getElementById('successModal');
            if (existingModal) {
                existingModal.remove();
            }
    
            document.body.insertAdjacentHTML('beforeend', modalHtml);
            const modal = new bootstrap.Modal(document.getElementById('successModal'));
            modal.show();
    
            document.getElementById('successModal').addEventListener('hidden.bs.modal', function () {
                this.remove();
            });
    
        } else {
            alert(`${title}\n\n${message}`);
        }
    };
    
    // Dosya boyutunu formatla
    window.formatFileSize = (bytes) => {
        if (bytes === 0) return '0 B';
        const k = 1024;
        const sizes = ['B', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
    };
    
    // SignalR connection genişletmeleri
    if (window.signalRManager) {
        // Dosya mesajı gönderme fonksiyonu ekle
        window.signalRManager.sendFileMessage = async function (receiverId, fileName, fileUrl, fileType, eventMessage) {
            try {
                if (this.connection && this.connection.state === signalR.HubConnectionState.Connected) {
                    await this.connection.invoke("SendFileMessage", receiverId, fileName, fileUrl, fileType, eventMessage);
                    console.log(`Dosya mesajı gönderildi: ${fileName} to ${receiverId}`);
                } else {
                    console.warn('SignalR bağlantısı aktif değil');
                    throw new Error('Bağlantı hatası');
                }
            } catch (error) {
                console.error('Dosya mesajı gönderilemedi:', error);
                throw error;
            }
        };
    
        // Dosya mesajı alma event handler'ını ekle
        if (window.signalRManager.connection) {
            window.signalRManager.connection.on("ReceiveFileMessage", function (senderId, fileName, fileUrl, fileType, eventMessage) {
                console.log(`Dosya mesajı alındı: ${fileName} from ${senderId}`);
    
                // Blazor component'ine dosya mesajını bildir
                if (window.dotNetHelper) {
                    window.dotNetHelper.invokeMethodAsync('HandleReceiveFileMessage', senderId, fileName, fileUrl, fileType);
                }
    
                // Notification göster (opsiyonel)
                if ('Notification' in window && Notification.permission === 'granted') {
                    new Notification(`${eventMessage}`, {
                        body: `Dosya: ${fileName}`,
                        icon: '/favicon.ico'
                    });
                }
            });
        }
    }
    
    // Clipboard'a kopyala
    window.copyToClipboard = async (text) => {
        try {
            if (navigator.clipboard) {
                await navigator.clipboard.writeText(text);
            } else {
                // Fallback for older browsers
                const textArea = document.createElement('textarea');
                textArea.value = text;
                textArea.style.position = 'fixed';
                textArea.style.left = '-999999px';
                textArea.style.top = '-999999px';
                document.body.appendChild(textArea);
                textArea.focus();
                textArea.select();
                document.execCommand('copy');
                textArea.remove();
            }
            return true;
        } catch (err) {
            console.error('Clipboard kopyalama hatası:', err);
            return false;
        }
    };
    
    // Local storage wrapper (error handling ile)
    window.chatStorage = {
        setItem: function (key, value) {
            try {
                localStorage.setItem(key, JSON.stringify(value));
                return true;
            } catch (e) {
                console.warn('LocalStorage yazma hatası:', e);
                return false;
            }
        },
    
        getItem: function (key) {
            try {
                const item = localStorage.getItem(key);
                return item ? JSON.parse(item) : null;
            } catch (e) {
                console.warn('LocalStorage okuma hatası:', e);
                return null;
            }
        },
    
        removeItem: function (key) {
            try {
                localStorage.removeItem(key);
                return true;
            } catch (e) {
                console.warn('LocalStorage silme hatası:', e);
                return false;
            }
        }
    };
    
    // Dosya drag & drop desteği
    window.initFileDragDrop = (dropZoneId, fileInputId, onFileSelected) => {
        const dropZone = document.getElementById(dropZoneId);
        const fileInput = document.getElementById(fileInputId);
    
        if (!dropZone || !fileInput) return;
    
        // Drag events
        dropZone.addEventListener('dragover', function (e) {
            e.preventDefault();
            dropZone.classList.add('drag-over');
        });
    
        dropZone.addEventListener('dragleave', function (e) {
            e.preventDefault();
            dropZone.classList.remove('drag-over');
        });
    
        dropZone.addEventListener('drop', function (e) {
            e.preventDefault();
            dropZone.classList.remove('drag-over');
    
            const files = e.dataTransfer.files;
            if (files.length > 0) {
                fileInput.files = files;
                if (onFileSelected && typeof onFileSelected === 'function') {
                    onFileSelected(files[0]);
                }
            }
        });
    };
    
    console.log('Chat helpers loaded successfully');