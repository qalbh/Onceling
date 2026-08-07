/**
 * Import function triggers from their respective submodules:
 *
 * import {onCall} from "firebase-functions/v2/https";
 * import {onDocumentWritten} from "firebase-functions/v2/firestore";
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

import { setGlobalOptions } from "firebase-functions";

// Cost control: cap concurrent containers per function. Override per-function
// with the `maxInstances` option where one genuinely needs more.
//
// **Region is asia-south1 to match Firestore**, and this was a real finding
// from the first deploy (**P2-16**). Without it, callables take the
// us-central1 default while the database sits in asia-south1: every one of
// them would cross a continent to read the document it was called about, and
// the Firestore trigger would be the only function co-located with its own
// data. The client must name the same region — see `functionsProvider`.
setGlobalOptions({ maxInstances: 10, region: "asia-south1" });

export {
  cancelPairingRequest,
  ensurePairingCode,
  requestPairing,
  respondToPairing,
} from "./pairing.js";
export { setMood } from "./mood.js";
export {
  notifyOnItem,
  notifyOnPairingAccepted,
  notifyOnPairingRequest,
} from "./notify.js";
export { ensureUserProfile, markOnboardingSeen } from "./profile.js";
export {
  beginReveal,
  completeReveal,
  sweepExpiredRevealsScheduled,
} from "./secret.js";
export { updateStreaksScheduled } from "./streak.js";
export { setAnniversary } from "./anniversary.js";
export { sweepUnpairedCouple, unpair } from "./unpair.js";
