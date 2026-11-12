(* The in-page devtools panel (reativa.devtools). *)

open Reativa
open Harness

let register () =
  suite "Devtools panel";
  async "shows events and explains an inspected element" (fun done_ ->
    Devtools.install ();
    let count = Signal.make ~name:"count" 0 in
    let label = Computed.make ~name:"label" (fun () -> "n=" ^ string_of_int (Signal.get count)) in
    let app = mount (View.p ~attrs:[ View.Attr.id (View.static "out") ] [ View.text (View.signal label) ]) in
    let host = Probe.container () in
    let unmount = Reativa_devtools.Panel.mount ~target:host () in
    Signal.set count 1;
    (* the panel refreshes in a microtask *)
    Probe.set_timeout 0 (fun () ->
    let panel_text = Probe.text_content host in
    let contains s sub =
      let n = String.length sub in
      let rec go i = i + n <= String.length s && (String.sub s i n = sub || go (i + 1)) in
      go 0
    in
    check "counts" (contains panel_text "1 signals");
    check "the write is listed" (contains panel_text "count <- 1");
    (* inspect: arm, then click the app's <p> *)
    let buttons = Probe.query_all host "button" in
    Probe.click (List.hd buttons);
    Probe.click (Option.get (Probe.query app "#out"));
    let explained = Probe.text_content host in
    check "why names the computed" (contains explained "computed label (recomputed)");
    check "and the write" (contains explained "signal count (written = 1)");
    unmount ();
    equal_string "unmounted" ~expected:"" (Probe.inner_html host);
    Devtools.uninstall ();
    done_ ()))
