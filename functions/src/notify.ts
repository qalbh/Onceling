import { getApps, initializeApp } from "firebase-admin/app";
import { Firestore, getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import {
  onDocumentCreated,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";

if (getApps().length === 0) initializeApp();

/**
 * **What a notification is allowed to say (P3-04, brief §10).**
 *
 * A lock screen is a public surface. Anyone holding the phone reads it, and
 * for a secret that is fatal: "Maya: I've never told you this…" on a lock
 * screen means the secret has been read while the app never registered an
 * open, the body was never deleted, and the sender is told nothing. The
 * one-time-open mechanic is defeated end to end by a preview.
 *
 * So: **a secret notification carries the sender and nothing else. Not
 * negotiable, not configurable.**
 *
 * For the other four types the honest answer is less obvious, and the reason
 * it is a SETTING rather than a fixed rule is brief §5 — it names couples who
 * share devices, and they are exactly the people for whom a warm, useful
 * preview is the wrong default. Someone on their own phone wants to read
 * "be there in ten" without unlocking; someone whose partner's sister borrows
 * the tablet does not. Neither is a mistake, so neither is a default that fits
 * everyone.
 *
 * The default is PREVIEWS OFF. A person who wants more can choose it; a person
 * who did not know to look is not exposed by our choice. The reverse default
 * would leak once before anyone learned the setting existed.
 */
export const SECRET_NOTIFICATION_BODY = "sent you a secret";

/** Fallback when a name is missing — never render an empty notification. */
export const FALLBACK_NAME = "Your person";

/** Longest preview a notification will carry. */
export const MAX_PREVIEW = 120;

type ItemType = "text" | "photo" | "emoji" | "status" | "secret";

interface NotificationCopy {
  title: string;
  body: string;
}

/**
 * Builds the notification for one item.
 *
 * @param {ItemType} type the item's type
 * @param {string} senderName who sent it
 * @param {string | null} preview the item's text, if previews are allowed
 * @return {NotificationCopy} what the lock screen will show
 */
export function notificationFor(
  type: ItemType,
  senderName: string,
  preview: string | null,
): NotificationCopy {
  const who = senderName.trim() === "" ? FALLBACK_NAME : senderName.trim();

  // The one case with no discretion. Note it ignores `preview` entirely rather
  // than checking a setting — there is no configuration in which a secret's
  // words reach a lock screen.
  if (type === "secret") {
    return { title: who, body: SECRET_NOTIFICATION_BODY };
  }

  const shown = preview == null ? null : preview.trim().slice(0, MAX_PREVIEW);

  switch (type) {
    case "text":
      return {
        title: who,
        body: shown != null && shown !== "" ? shown : "sent you a message",
      };
    case "photo":
      // A caption is text and gets the same treatment; without previews the
      // fact of a photo is not sensitive in the way its content is.
      return {
        title: who,
        body: shown != null && shown !== "" ? shown : "sent you a photo",
      };
    case "emoji":
      // The emoji IS the message and is a single character. Withholding it
      // would say "sent you a reaction" about something that is already less
      // revealing than the notification announcing it.
      return { title: who, body: shown != null && shown !== "" ? shown : "💛" };
    case "status":
      return {
        title: who,
        body: shown != null && shown !== "" ? shown : "updated their mood",
      };
    default:
      return { title: who, body: "sent you something" };
  }
}

export interface Recipient {
  uid: string;
  token: string | null;
  previews: boolean;
}

/** Reads the couple's other member: their token and their preview setting.
 *
 * @param {Firestore} db the admin Firestore handle
 * @param {string} coupleId the couple to look in
 * @param {string} senderId the person who caused the event
 * @return {Promise<Recipient | null>} the partner, or null if unreachable
 */
async function partnerOf(
  db: Firestore,
  coupleId: string,
  senderId: string,
): Promise<Recipient | null> {
  const couple = await db.doc(`couples/${coupleId}`).get();
  if (!couple.exists) return null;

  const members = (couple.data()?.memberIds ?? []) as string[];
  const uid = members.find((m) => m !== senderId);
  if (uid == null) return null;

  const profile = await db.doc(`users/${uid}`).get();
  if (!profile.exists) return null;

  return {
    uid,
    token: (profile.data()?.pushToken as string | undefined) ?? null,
    // Default OFF — see the note on SECRET_NOTIFICATION_BODY.
    previews: profile.data()?.notificationPreviews === true,
  };
}

/** Sends one notification, tolerating a dead token.
 *
 * Exported since **P3-03**: the milestone path sends to both partners and
 * lives in its own module, and duplicating the dead-token cleanup there would
 * mean two places that must agree about what a dead token is.
 *
 * @param {Firestore} db the admin Firestore handle
 * @param {Recipient} to who to notify
 * @param {NotificationCopy} copy the title and body
 * @param {Record<string, string>} data payload for in-app routing
 * @return {Promise<boolean>} whether it was delivered
 */
export async function send(
  db: Firestore,
  to: Recipient,
  copy: NotificationCopy,
  data: Record<string, string>,
): Promise<boolean> {
  if (to.token == null) return false;
  try {
    await getMessaging().send({
      token: to.token,
      notification: { title: copy.title, body: copy.body },
      data,
      apns: { payload: { aps: { sound: "default" } } },
      android: { priority: "high" },
    });
    return true;
  } catch (error) {
    const code = (error as { code?: string }).code ?? "";
    // A token dies when the app is uninstalled or the token rotates while the
    // device is offline. Clearing it stops us retrying forever, and matters
    // for the same reason sign-out clears it: a token we cannot reach is not
    // harmless, it is a token pointing somewhere we no longer understand.
    if (
      code.includes("registration-token-not-registered") ||
      code.includes("invalid-argument")
    ) {
      await db
        .doc(`users/${to.uid}`)
        .set({ pushToken: null }, { merge: true })
        .catch(() => undefined);
    }
    console.warn(`[P3-04] send to ${to.uid} failed: ${error}`);
    return false;
  }
}

/**
 * **P3-04** — a new thread item notifies the other person.
 *
 * Never the sender: `partnerOf` excludes them by construction rather than by a
 * comparison someone could forget to write.
 */
export const notifyOnItem = onDocumentCreated(
  "items/{itemId}",
  async (event) => {
    const item = event.data?.data();
    if (item == null) return;

    const coupleId = item.coupleId as string | undefined;
    const senderId = item.senderId as string | undefined;
    const type = item.type as ItemType | undefined;
    if (coupleId == null || senderId == null || type == null) return;

    const db = getFirestore();
    const to = await partnerOf(db, coupleId, senderId);
    if (to == null || to.token == null) return;

    const couple = await db.doc(`couples/${coupleId}`).get();
    const names = (couple.data()?.memberNames ?? {}) as Record<string, string>;

    // Previews are read from the RECIPIENT's profile, not the sender's: it is
    // the recipient's lock screen and their device that might be shared.
    const preview = to.previews
      ? ((item.body as string | undefined) ??
        (item.emoji as string | undefined) ??
        null)
      : null;

    const copy = notificationFor(
      type,
      names[senderId] ?? FALLBACK_NAME,
      preview,
    );
    await send(db, to, copy, {
      kind: "item",
      itemId: event.params.itemId,
      itemType: type,
    });
  },
);

/**
 * **P3-04** — someone is asking to pair.
 *
 * This is what lets **P2-24**'s waiting screen stop saying the partner will
 * see it next time they open the app.
 */
export const notifyOnPairingRequest = onDocumentCreated(
  "pairingRequests/{requestId}",
  async (event) => {
    const request = event.data?.data();
    if (request == null || request.status !== "pending") return;

    const toUid = request.toUid as string | undefined;
    if (toUid == null) return;

    const db = getFirestore();
    const profile = await db.doc(`users/${toUid}`).get();
    const token = (profile.data()?.pushToken as string | undefined) ?? null;
    if (token == null) return;

    // The sender's name is already denormalised onto the request (P2-25), so
    // this costs no extra read — and it is bounded there, which matters
    // because it is user text landing on someone else's lock screen.
    const from =
      (request.fromDisplayName as string | undefined) ?? FALLBACK_NAME;

    await send(
      db,
      { uid: toUid, token, previews: false },
      { title: from, body: "wants to pair with you" },
      { kind: "pairingRequest", requestId: event.params.requestId },
    );
  },
);

/**
 * **P3-04** — a request was accepted, so the SENDER learns they are paired.
 *
 * Only on accept. A decline writes `expired`, and telling the sender about
 * that would undo **PI-05** — they are never told a person refused.
 */
export const notifyOnPairingAccepted = onDocumentUpdated(
  "pairingRequests/{requestId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (before?.status !== "pending" || after?.status !== "accepted") return;

    const fromUid = after.fromUid as string | undefined;
    const coupleId = after.coupleId as string | undefined;
    if (fromUid == null) return;

    const db = getFirestore();
    const profile = await db.doc(`users/${fromUid}`).get();
    const token = (profile.data()?.pushToken as string | undefined) ?? null;
    if (token == null) return;

    // Name the person who accepted, read from the couple the accept created.
    let who = FALLBACK_NAME;
    if (coupleId != null) {
      const couple = await db.doc(`couples/${coupleId}`).get();
      const names = (couple.data()?.memberNames ?? {}) as Record<
        string,
        string
      >;
      const other = Object.keys(names).find((uid) => uid !== fromUid);
      if (other != null && names[other]) who = names[other];
    }

    await send(
      db,
      { uid: fromUid, token, previews: false },
      { title: who, body: "said yes. Your space is open." },
      { kind: "pairingAccepted" },
    );
  },
);
