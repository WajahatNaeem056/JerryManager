// Browser-only fallback: when the page is opened outside a root manager there is
// no window.ksu, so a no-op shim is installed and /json/info.json is faked.
if (window.ksu === undefined) {
    const shim = {
        exec(command, options, callbackName) {
            setTimeout(() => {
                const cb = window[callbackName];
                typeof cb == `function` && cb(0, ``, ``);
            }, 50);
        },
        spawn(command, args, options, handlerName) {
            const handler = window[handlerName];
            handler && setTimeout(() => {
                handler.stdout?.emit?.(`data`, ``);
                handler.emit?.(`exit`, 0);
            }, 100);
        },
    };
    Object.defineProperty(window, `ksu`, { get() { return shim; }, configurable: true });

    const realFetch = window.fetch.bind(window);
    const jsonResponse = (obj) => new Response(JSON.stringify(obj), { status: 200, headers: { 'Content-Type': `application/json` } });
    window.fetch = function (input, ...rest) {
        const url = typeof input == `string` ? input : input.url;
        if (url.startsWith(`/json/module_paths.json`)) {
            return realFetch(url, ...rest).then(res => {
                const type = res.headers.get(`content-type`) || ``;
                if (!res.ok || !type.includes(`json`))
                    throw Error(`not found`);
                return res;
            }).catch(() => Promise.resolve(jsonResponse({ MODDIR: `/data/adb/modules/JerryManager` })));
        }
        if (url.includes(`/json/info.json`))
            return Promise.resolve(jsonResponse({ android: `14`, kernel: `6.1.0`, root: `KernelSU` }));
        return realFetch(url, ...rest);
    };
}
