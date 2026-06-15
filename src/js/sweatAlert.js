// ✅ TAMAMEN YENİ VERSİYON - Cache sorununu önlemek için
window.showConfirmDialog = function(title, message, confirmText, cancelText) {
    confirmText = confirmText || 'Evet';
    cancelText = cancelText || 'Vazgeç';

    return new Promise(function(resolve) {
        Swal.fire({
            title: title,
            text: message,
            icon: 'warning',
            showCancelButton: true,
            confirmButtonColor: '#d33',
            cancelButtonColor: '#3085d6',
            confirmButtonText: confirmText,
            cancelButtonText: cancelText
        }).then(function(result) {
            // ✅ SADECE BOOLEAN DÖNDÜR
            if (result.isConfirmed === true) {
                resolve(true);
            } else {
                resolve(false);
            }
        });
    });
};
window.showErrorDialog = function(title, message, buttonText) {
    buttonText = buttonText || 'OK';

    var options = {
        title: title,
        icon: 'error',
        confirmButtonColor: '#d33',
        confirmButtonText: buttonText
    };

    if (message) {
        options.text = message;
    }

    return Swal.fire(options);
};

window.showSuccessDialog = function(title, message) {
    var options = {
        icon: 'success',
        title: title,
        showConfirmButton: false,
        timer: 1500
    };

    if (message) {
        options.text = message;
    }

    return Swal.fire(options);
};

// ✅ BONUS: Console'a yaz ki fonksiyon yüklendiğini görelim
console.log('✅ SweetAlert dialogs loaded');