import "../../shared/bench.css";
/* The Melange output of bench_app.ml; build.mjs aliases this to _build. */
import "@reativa-bench-app";

/* Startup marker read by the benchmark driver. */
window.__BENCH_READY_AT__ = performance.now();
window.__BENCH_READY__ = true;
