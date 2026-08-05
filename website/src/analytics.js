// PostHog analytics for the documentation site and the playground.
//
// The project key comes from the build environment (VITE_POSTHOG_KEY), so a
// clone, a fork's Pages build and `npm run docs:dev` all stay silent by
// default — only a build that was handed a key reports anything. Every export
// below degrades to a no-op without one, so call sites never have to check.
//
// See website/.env.example for the variables and README.md ("Analytics") for
// how the deploy passes them in.

const KEY = import.meta.env.VITE_POSTHOG_KEY;
const HOST = import.meta.env.VITE_POSTHOG_HOST || "https://us.i.posthog.com";

export const analyticsEnabled = Boolean(KEY);

// Resolved once the SDK has loaded and initialised; until then events wait in
// [pending]. The cap is a backstop for the case where the import never lands.
let client = null;
const pending = [];
const PENDING_LIMIT = 50;

// Testing the raw variable rather than the flag lets the bundler fold the
// branch away entirely: a build without a key emits no PostHog chunk at all.
if (KEY) {
  // Out of band, and only in a build that reports: the SDK is an order of
  // magnitude larger than the page it measures, so it has no business in the
  // critical path — and a build without a key never fetches the chunk at all.
  import("posthog-js")
    .then(({ default: posthog }) => {
      posthog.init(KEY, {
        api_host: HOST,

        // Static pages with no client-side router, so one pageview per
        // document load is the whole story. The modern default
        // ('history_change') would count every in-page anchor — #why,
        // #examples, #api — as another pageview.
        capture_pageview: true,
        capture_pageleave: true,

        // The events below are named and deliberate; autocaptured DOM clicks
        // would only add noise on top of them.
        autocapture: false,

        // Nobody signs in here, so there is no one to build a person profile
        // for; events stay anonymous.
        person_profiles: "never",
        respect_dnt: true,

        // The playground editor holds whatever the visitor is writing.
        // Recording is off unless a project turns it on, and it must stay off
        // here: their code is theirs.
        disable_session_recording: true,
      });

      client = posthog;
      for (const [event, properties] of pending.splice(0)) {
        posthog.capture(event, properties);
      }
    })
    .catch(() => {
      /* blocked, offline or ad-filtered — the page does not care */
    });
}

// Named events for the interactions worth counting. Anything that throws (a
// blocked request, an extension that stubbed the SDK out) is swallowed:
// analytics must never be what breaks the page.
export function track(event, properties) {
  if (!analyticsEnabled) return;
  if (!client) {
    if (pending.length < PENDING_LIMIT) pending.push([event, properties]);
    return;
  }
  try {
    client.capture(event, properties);
  } catch (error) {
    /* reporting is best-effort */
  }
}
