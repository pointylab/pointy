"use strict";
// Typed access to the Go services and events of the generated client,
// over window.mygo. Go injects this script with a page's adapter, in one
// scope, before the page's own scripts.
function goService(name) {
    return new Proxy({}, {
        get: (_, method) => (...args) => window.mygo.call(`${name}.${method[0].toUpperCase()}${method.slice(1)}`, ...args),
    });
}
const goEvents = new Proxy({}, {
    get: (_, name) => ({
        name,
        on: (listener) => window.mygo.on(name, listener),
        once: (listener) => window.mygo.once(name, listener),
    }),
});
