"use strict";
window.__ModuleLoader__.load({
    id: "@pointylab/dsh",
    factory: () => {
        var module = { exports: {} };
        var exports = module.exports;
        Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });
        const RPC_CHANNEL = "/pointy";
        const RETRY_MS = 3000;
        const inject = ["connection", "uiWorkspace"];
        function apply(ctx) {
            const connection = ctx.get("connection");
            let alive = true;
            ctx.effect(() => () => { alive = false; }, "pointy: focus loop");
            (async () => {
                while (alive) {
                    try {
                        const result = await connection.rpc.call(RPC_CHANNEL, "next-focus", { origin: location.origin });
                        if (!alive)
                            break;
                        if (result?.ok && typeof result.value === "string")
                            ctx.uiWorkspace.openSession(result.value);
                    }
                    catch {
                        await new Promise((r) => setTimeout(r, RETRY_MS));
                    }
                }
            })();
        }
        exports.apply = apply;
        exports.inject = inject;
        return module.exports;
    }
});
