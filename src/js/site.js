window.setVideoAspectRatio = (container) => {
    if (!container) return;

    const video = container.querySelector("video");
    if (!video || !video.videoWidth) return;

    const ratio = video.videoWidth / video.videoHeight;

    container.style.aspectRatio = ratio;

    if (ratio < 1) {
        container.style.maxHeight = "420px"; // dikey video
    } else {
        container.style.maxHeight = "260px"; // yatay video
    }
};
window.addOutsideClickListener = (dotNetHelper) => {
    document.addEventListener('click', (event) => {
        // Tıklanan eleman bir bildirim butonu veya modalın kendisi değilse Blazor'a haber ver
        const isClickInside = event.target.closest('.notification-container');

        if (!isClickInside) {
            dotNetHelper.invokeMethodAsync('CloseModalsOutside');
        }
    });
};