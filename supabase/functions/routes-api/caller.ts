import { HttpError } from "./http.ts";

export type Caller = {
  uid: string;
  role: "rider" | "moderator" | "superadmin";
  blocked: boolean;
  name: string;
  // When the account was made, if the profile says. S_NEW_CONTRIBUTOR uses it.
  createdAt: string | null;
};

// A value as the Firestore REST API sends it, like { stringValue: "x" }.
type FirestoreValue = {
  stringValue?: string;
  booleanValue?: boolean;
  timestampValue?: string;
};

function isInFuture(value: FirestoreValue | undefined): boolean {
  // The app can save this date as text, so accept both forms. It's safer to
  // block a rider the app also treats as restricted than to let them through.
  const date = value?.timestampValue ?? value?.stringValue;
  if (!date) return false;
  return new Date(date).getTime() > Date.now();
}

// Reads users/{uid} with the rider's own login, so this function needs no
// Google service account. Firestore rules let any signed-in user read it, and
// riders can't change their own role or ban state.
export async function fetchCaller(
  uid: string,
  idToken: string,
  projectId: string,
  fetchFn: typeof fetch = fetch,
): Promise<Caller> {
  const url =
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/users/${
      encodeURIComponent(uid)
    }`;
  const response = await fetchFn(url, {
    headers: { Authorization: `Bearer ${idToken}` },
  });

  // A brand new account may not have its profile doc yet.
  if (response.status === 404) {
    await response.body?.cancel();
    return { uid, role: "rider", blocked: false, name: "", createdAt: null };
  }
  if (response.status === 401 || response.status === 403) {
    await response.body?.cancel();
    throw new HttpError(401, "unauthenticated");
  }
  // Without the doc we can't tell if this rider is banned, so refuse the call.
  if (!response.ok) {
    await response.body?.cancel();
    throw new HttpError(503, "unavailable");
  }

  const doc = await response.json();
  const fields: Record<string, FirestoreValue> = doc.fields ?? {};

  const savedRole = fields.role?.stringValue;
  const role = savedRole === "moderator" || savedRole === "superadmin"
    ? savedRole
    : "rider";
  const status = (fields.status?.stringValue ?? "").trim().toLowerCase();

  return {
    uid,
    role,
    blocked: fields.isBanned?.booleanValue === true ||
      status === "banned" ||
      isInFuture(fields.restrictedUntil),
    name: fields.name?.stringValue ?? "",
    createdAt: fields.createdAt?.timestampValue ?? fields.createdAt?.stringValue ?? null,
  };
}

export function isStaff(caller: Caller): boolean {
  return caller.role === "moderator" || caller.role === "superadmin";
}
