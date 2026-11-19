export const themeStorageKey = "ngaon-theme";

/** Inlined in <head>: applies a saved light/dark choice before first paint (no flash). */
export const themeBootScript = `(function(){try{var t=localStorage.getItem('${themeStorageKey}');if(t==='light'||t==='dark')document.documentElement.dataset.theme=t;}catch(e){}})();`;
