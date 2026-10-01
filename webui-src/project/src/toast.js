
export function showToast(message, options = {}) {
    let { action: action, autoCloseDelay: autoCloseDelay = 3e3, onActionClick: onActionClick, className: className } = options;
    let toast = document.createElement(`div`);
    return toast.className = `md-toast` + (className ? ` ` + className : ``), toast.innerHTML = `
    <span class="md-toast__message">${message}</span>
    ${action ? `<button class="md-toast__action">${action}</button>` : ``}
  `, (className === `snackbar-success` ? document.getElementById(`top-bar`) || document.body : document.body).appendChild(toast), requestAnimationFrame(() => toast.classList.add(`md-toast--open`)), action && onActionClick && (toast.querySelector(`.md-toast__action`).onclick = () => {
        dismissToast(toast);
        onActionClick();
    }), autoCloseDelay > 0 && (toast._autoTimer = setTimeout(() => dismissToast(toast), autoCloseDelay)), setTimeout(() => {
        toast.parentNode && toast.parentNode.removeChild(toast);
    }, 8e3), enableToastSwipeDismiss(toast, autoCloseDelay), toast;
}
function enableToastSwipeDismiss(toast, autoCloseDelay) {
    let startX = 0;
    let deltaX = 0;
    let dragging = false;
    let onDown = i => {
        startX = i.clientX;
        deltaX = 0;
        dragging = true;
        toast.style.transition = `none`;
        toast._autoTimer &&= (clearTimeout(toast._autoTimer), null);
    };
    let onMove = i => {
        if (!dragging)
            return;
        deltaX = i.clientX - startX;
        deltaX < 0 && (deltaX = 0);
        let a = window.innerWidth * .4;
        let onUp = Math.min(deltaX, a);
        toast.style.transform = `translateX(calc(-50% + ${onUp}px)) translateY(0)`;
    };
    let o = () => {
        dragging && (dragging = false, toast.style.transition = ``, deltaX > 80 ? dismissToastBySwipe(toast) : (toast.style.transform = ``, toast.classList.add(`md-toast--open`), autoCloseDelay > 0 && (toast._autoTimer = setTimeout(() => dismissToast(toast), autoCloseDelay))));
    };
    toast.addEventListener(`pointerdown`, onDown, { passive: true });
    toast.addEventListener(`pointermove`, onMove, { passive: true });
    toast.addEventListener(`pointerup`, o);
    toast.addEventListener(`pointercancel`, o);
}
function dismissToastBySwipe(toast) {
    toast.classList.remove(`md-toast--open`);
    toast.classList.add(`md-toast--dismiss`);
    toast.addEventListener(`transitionend`, () => {
        toast.parentNode && toast.parentNode.removeChild(toast);
    }, { once: true });
    setTimeout(() => {
        toast.parentNode && toast.parentNode.removeChild(toast);
    }, 300);
}
function dismissToast(toast) {
    toast.classList.remove(`md-toast--open`);
    toast.addEventListener(`transitionend`, () => {
        toast.parentNode && toast.parentNode.removeChild(toast);
    }, { once: true });
    setTimeout(() => {
        toast.parentNode && toast.parentNode.removeChild(toast);
    }, 300);
}
