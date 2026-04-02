import {
  Timestamp,
  addDoc,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  limit,
  onSnapshot,
  orderBy,
  query,
  serverTimestamp,
  updateDoc,
  where,
  type QueryDocumentSnapshot,
  type DocumentData,
} from 'firebase/firestore'
import { httpsCallable } from 'firebase/functions'
import { db, functionsClient } from '@/lib/firebase'
import type {
  AnnouncementItem,
  AppUser,
  DashboardActivity,
  DashboardStats,
  FeedbackItem,
  PostItem,
  RouteItem,
  UserRole,
} from '@/types/models'

const usersCol = collection(db, 'users')
const routesCol = collection(db, 'routes')
const postsCol = collection(db, 'posts')
const feedbackCol = collection(db, 'feedbacks')
const announcementsCol = collection(db, 'announcements')

function normalizeTimestamp(value: unknown): Timestamp | undefined {
  if (!value) return undefined
  if (value instanceof Timestamp) return value
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return Timestamp.fromDate(value)
  }
  if (typeof value === 'string' || typeof value === 'number') {
    const date = new Date(value)
    if (!Number.isNaN(date.getTime())) {
      return Timestamp.fromDate(date)
    }
  }

  if (typeof value === 'object' && value !== null) {
    const maybeSeconds = (value as { seconds?: unknown }).seconds
    const maybeNanos = (value as { nanoseconds?: unknown }).nanoseconds
    if (typeof maybeSeconds === 'number') {
      return new Timestamp(maybeSeconds, typeof maybeNanos === 'number' ? maybeNanos : 0)
    }
  }

  return undefined
}

async function getDocsWithCreatedAtFallback(colRef: ReturnType<typeof collection>) {
  const safeGet = async (loader: () => Promise<QueryDocumentSnapshot<DocumentData>[]>) => {
    try {
      return await loader()
    } catch {
      return [] as QueryDocumentSnapshot<DocumentData>[]
    }
  }

  const [createdAtDocs, timestampDocs, plainDocs] = await Promise.all([
    safeGet(async () => (await getDocs(query(colRef, orderBy('createdAt', 'desc'), limit(500)))).docs),
    safeGet(async () => (await getDocs(query(colRef, orderBy('timestamp', 'desc'), limit(500)))).docs),
    safeGet(async () => (await getDocs(query(colRef, limit(500)))).docs),
  ])

  const merged = new Map<string, QueryDocumentSnapshot<DocumentData>>()
  ;[...createdAtDocs, ...timestampDocs, ...plainDocs].forEach((docSnap) => {
    merged.set(docSnap.id, docSnap)
  })

  return sortDocsByCreatedAtDesc([...merged.values()])
}

function sortDocsByCreatedAtDesc<T extends QueryDocumentSnapshot<DocumentData>>(docs: T[]) {
  return docs.sort((a, b) => {
    const aTs = normalizeTimestamp(a.data().createdAt ?? a.data().timestamp)
    const bTs = normalizeTimestamp(b.data().createdAt ?? b.data().timestamp)
    if (!aTs && !bTs) return 0
    if (!aTs) return 1
    if (!bTs) return -1
    return bTs.toMillis() - aTs.toMillis()
  })
}

function subscribeWithTimestampFallback(
  colRef: ReturnType<typeof collection>,
  onNext: (docs: QueryDocumentSnapshot<DocumentData>[]) => void,
  onFailure: (error: unknown) => void,
) {
  let createdAtDocs: QueryDocumentSnapshot<DocumentData>[] = []
  let timestampDocs: QueryDocumentSnapshot<DocumentData>[] = []
  let plainDocs: QueryDocumentSnapshot<DocumentData>[] = []

  const emitMerged = () => {
    const merged = new Map<string, QueryDocumentSnapshot<DocumentData>>()
    ;[...createdAtDocs, ...timestampDocs, ...plainDocs].forEach((docSnap) => {
      merged.set(docSnap.id, docSnap)
    })
    onNext(sortDocsByCreatedAtDesc([...merged.values()]))
  }

  const unsubCreatedAt = onSnapshot(
    query(colRef, orderBy('createdAt', 'desc'), limit(300)),
    (snap) => {
      createdAtDocs = [...snap.docs]
      emitMerged()
    },
    (err) => onFailure(err),
  )

  const unsubTimestamp = onSnapshot(
    query(colRef, orderBy('timestamp', 'desc'), limit(300)),
    (snap) => {
      timestampDocs = [...snap.docs]
      emitMerged()
    },
    () => {
      timestampDocs = []
      emitMerged()
    },
  )

  const unsubPlain = onSnapshot(
    query(colRef, limit(300)),
    (snap) => {
      plainDocs = [...snap.docs]
      emitMerged()
    },
    (err) => onFailure(err),
  )

  return () => {
    unsubCreatedAt()
    unsubTimestamp()
    unsubPlain()
  }
}

function toDateLabel(ts?: Timestamp) {
  if (!ts) return 'Unknown'
  return ts.toDate().toLocaleDateString('en-PH', { month: 'short', day: 'numeric' })
}

function toRelativeTimeLabel(ts?: Timestamp) {
  if (!ts) return 'Unknown'
  const now = Date.now()
  const diffMs = Math.max(0, now - ts.toMillis())
  const diffMins = Math.floor(diffMs / 60000)
  if (diffMins < 1) return 'Just now'
  if (diffMins < 60) return `${diffMins}m ago`
  const diffHours = Math.floor(diffMins / 60)
  if (diffHours < 24) return `${diffHours}h ago`
  const diffDays = Math.floor(diffHours / 24)
  if (diffDays < 7) return `${diffDays}d ago`
  return toDateLabel(ts)
}

function toTimestampMs(ts?: Timestamp) {
  return ts?.toMillis() ?? 0
}

function toDayBucketKey(ts?: Timestamp): number | null {
  if (!ts) return null
  const d = ts.toDate()
  d.setHours(0, 0, 0, 0)
  return d.getTime()
}

function toWeekBucketKey(ts?: Timestamp): number | null {
  if (!ts) return null
  const d = ts.toDate()
  d.setHours(0, 0, 0, 0)
  const start = new Date(d)
  start.setDate(d.getDate() - d.getDay())
  return start.getTime()
}

function dayBucketLabel(bucket: number) {
  return new Date(bucket).toLocaleDateString('en-PH', { month: 'short', day: 'numeric' })
}

function getFeedbackReason(data: DocumentData): string {
  const raw = data.reason ?? data.message ?? data.content
  if (typeof raw === 'string' && raw.trim().length > 0) return raw.trim()
  return 'No reason provided'
}

function resolveUserStatus(data: DocumentData): AppUser['status'] {
  if (data.isBanned || data.status === 'banned') return 'banned'

  if (data.status === 'active' || data.status === 'offline') {
    return data.status
  }

  const lastActive = normalizeTimestamp(
    data.lastActiveDate ?? data.lastSeenAt ?? data.updatedAt ?? data.timestamp,
  )

  if (!lastActive) return 'offline'

  const minutesSinceLastActive = Math.max(
    0,
    Math.floor((Date.now() - lastActive.toMillis()) / 60000),
  )

  return minutesSinceLastActive <= 15 ? 'active' : 'offline'
}

function mapUserDoc(d: QueryDocumentSnapshot<DocumentData>): AppUser {
  const data = d.data()
  return {
    id: d.id,
    name: data.displayName ?? data.name ?? data.userName ?? 'Unknown User',
    email: data.email ?? '',
    role: data.role ?? 'user',
    status: resolveUserStatus(data),
    createdAt: normalizeTimestamp(data.createdAt ?? data.timestamp),
    routesContributed: data.routesContributed ?? data.contributionCount ?? 0,
    badges: data.badges ?? [],
    achievements: data.achievements ?? [],
    streakDays: data.streakDays ?? 0,
    contributionCount: data.contributionCount ?? 0,
    userCategory: data.userCategory ?? 'all',
  } as AppUser
}

function mapRouteDoc(d: QueryDocumentSnapshot<DocumentData>): RouteItem {
  const data = d.data()
  const feedbackSummaryRaw = data.feedbackSummary as Record<string, unknown> | undefined
  return {
    id: d.id,
    startLocation: data.startLocation ?? data.from ?? 'Unknown',
    endLocation: data.endLocation ?? data.to ?? 'Unknown',
    contributorId: data.contributorId ?? data.userId ?? '',
    contributorName: data.contributorName ?? data.userName,
    contributorEmail: data.contributorEmail ?? data.userEmail ?? data.email,
    createdAt: normalizeTimestamp(data.createdAt ?? data.timestamp),
    updatedAt: normalizeTimestamp(data.updatedAt),
    status: data.approvalStatus ?? data.status ?? 'pending',
    views: data.views ?? 0,
    upvotes: data.upvotes ?? 0,
    downvotes: data.downvotes ?? 0,
    feedbackSummary: feedbackSummaryRaw
      ? {
          fareAccurateYes: Number(feedbackSummaryRaw.fareAccurateYes ?? 0),
          fareAccurateNo: Number(feedbackSummaryRaw.fareAccurateNo ?? 0),
          scheduleAccurateYes: Number(feedbackSummaryRaw.scheduleAccurateYes ?? 0),
          scheduleAccurateNo: Number(feedbackSummaryRaw.scheduleAccurateNo ?? 0),
          stillOperatingYes: Number(feedbackSummaryRaw.stillOperatingYes ?? 0),
          stillOperatingNo: Number(feedbackSummaryRaw.stillOperatingNo ?? 0),
        }
      : undefined,
    steps: data.steps ?? [],
    transportModes: data.transportModes ?? [],
    etaMinutes: data.etaMinutes,
    fareEstimate: data.fareEstimate,
    distanceKm: data.distanceKm,
  }
}

function mapPostDoc(d: QueryDocumentSnapshot<DocumentData>): PostItem {
  const data = d.data()
  const status = data.moderationStatus ?? 'pending'
  const isFlagged = Boolean(data.isFlagged)
  return {
    id: d.id,
    userId: data.userId ?? '',
    userName: (data.userName ?? '').trim(),
    userEmail: (data.userEmail ?? '').trim(),
    category: data.category ?? 'general',
    content: data.content ?? '',
    images: data.images ?? data.imageUrls ?? [],
    moderationStatus: isFlagged && status === 'pending' ? 'flagged' : status,
    isFlagged,
    createdAt: normalizeTimestamp(data.createdAt ?? data.timestamp),
  }
}

function buildDashboardStatsFromData(
  users: AppUser[],
  routes: RouteItem[],
  posts: PostItem[],
  feedbackDocs: QueryDocumentSnapshot<DocumentData>[],
): DashboardStats {
  const userGrowthMap = new Map<number, number>()
  users.forEach((u) => {
    const key = toDayBucketKey(u.createdAt)
    if (key === null) return
    userGrowthMap.set(key, (userGrowthMap.get(key) ?? 0) + 1)
  })

  const routesWeeklyMap = new Map<number, number>()
  routes.forEach((r) => {
    const key = toWeekBucketKey(r.createdAt)
    if (key === null) return
    routesWeeklyMap.set(key, (routesWeeklyMap.get(key) ?? 0) + 1)
  })

  const userGrowth = Array.from(userGrowthMap.entries())
    .sort(([a], [b]) => a - b)
    .map(([bucket, count]) => ({ label: dayBucketLabel(bucket), count }))
    .slice(-8)

  const routesPerWeek = Array.from(routesWeeklyMap.entries())
    .sort(([a], [b]) => a - b)
    .map(([bucket, count]) => ({ label: dayBucketLabel(bucket), count }))
    .slice(-8)

  const recentUsers: DashboardActivity[] = users.slice(0, 4).map((u) => ({
    id: `u-${u.id}`,
    type: 'signup',
    description: `${u.name} signed up`,
    time: toRelativeTimeLabel(u.createdAt),
    timestampMs: toTimestampMs(u.createdAt),
    severity: 'info',
  }))

  const recentRoutes: DashboardActivity[] = routes.slice(0, 4).map((r) => ({
    id: `r-${r.id}`,
    type: 'route',
    description: `Route submitted: ${r.startLocation} to ${r.endLocation}`,
    time: toRelativeTimeLabel(r.createdAt),
    timestampMs: toTimestampMs(r.createdAt),
    severity: 'info',
  }))

  const recentPosts: DashboardActivity[] = posts.slice(0, 4).map((p) => ({
    id: `p-${p.id}`,
    type: 'post',
    description: `New post: ${p.content.slice(0, 72)}${p.content.length > 72 ? '...' : ''}`,
    time: toRelativeTimeLabel(p.createdAt),
    timestampMs: toTimestampMs(p.createdAt),
    severity: p.isFlagged ? 'warning' : 'info',
  }))

  const recentReports: DashboardActivity[] = feedbackDocs
    .filter((f) => String(f.data().type ?? 'feedback') === 'report')
    .slice(0, 4)
    .map((f) => {
      const ts = normalizeTimestamp(f.data().createdAt ?? f.data().timestamp)
      const reason = getFeedbackReason(f.data())
      return {
        id: `f-${f.id}`,
        type: 'report',
        description: `Reported content: ${reason}`,
        time: toRelativeTimeLabel(ts),
        timestampMs: toTimestampMs(ts),
        severity: 'warning' as const,
      }
    })

  const recentActivity = [...recentUsers, ...recentRoutes, ...recentPosts, ...recentReports]
    .sort((a, b) => b.timestampMs - a.timestampMs)
    .slice(0, 12)

  return {
    totalUsers: users.length,
    activeUsers: users.filter((u) => u.status === 'active').length,
    bannedUsers: users.filter((u) => u.status === 'banned').length,
    routes: {
      approved: routes.filter((r) => r.status === 'approved').length,
      pending: routes.filter((r) => r.status === 'pending').length,
      rejected: routes.filter((r) => r.status === 'rejected').length,
    },
    posts: {
      approved: posts.filter((p) => p.moderationStatus === 'approved').length,
      pending: posts.filter((p) => p.moderationStatus === 'pending').length,
      flagged: posts.filter((p) => p.moderationStatus === 'flagged' || p.isFlagged).length,
    },
    userGrowth,
    routesPerWeek,
    recentActivity,
  }
}

export async function getCurrentUserRole(uid: string): Promise<UserRole | null> {
  const userSnap = await getDoc(doc(db, 'users', uid))
  if (!userSnap.exists()) return null
  const role = (userSnap.data().role ?? 'user') as UserRole
  return role
}

export async function getUsers(): Promise<AppUser[]> {
  const docs = await getDocsWithCreatedAtFallback(usersCol)
  return docs.map(mapUserDoc)
}

export async function updateUserRole(userId: string, role: UserRole) {
  await updateDoc(doc(db, 'users', userId), { role, updatedAt: serverTimestamp() })
}

export async function setUserBanStatus(userId: string, isBanned: boolean) {
  await updateDoc(doc(db, 'users', userId), {
    isBanned,
    status: isBanned ? 'banned' : 'active',
    updatedAt: serverTimestamp(),
  })
}

export async function deleteUser(userId: string) {
  const callable = httpsCallable<{ userId: string }, { ok?: boolean }>(
    functionsClient,
    'adminDeleteUserAccount',
  )

  try {
    await callable({ userId })
    return
  } catch {
    // Fallback keeps legacy behavior when functions are not yet deployed.
    await deleteDoc(doc(db, 'users', userId))
  }
}

export async function getRoutes(): Promise<RouteItem[]> {
  const [routeDocs, userDocs] = await Promise.all([
    getDocsWithCreatedAtFallback(routesCol),
    getDocsWithCreatedAtFallback(usersCol),
  ])

  const contributorLookup = new Map<string, { name?: string; email?: string }>()
  userDocs.forEach((userDoc) => {
    const data = userDoc.data()
    const nameRaw = data.displayName ?? data.name ?? data.userName
    const emailRaw = data.email
    const name = typeof nameRaw === 'string' ? nameRaw.trim() : ''
    const email = typeof emailRaw === 'string' ? emailRaw.trim() : ''
    contributorLookup.set(userDoc.id, {
      name: name || undefined,
      email: email || undefined,
    })
  })

  return routeDocs.map((docSnap) => {
    const route = mapRouteDoc(docSnap)
    const lookup = route.contributorId ? contributorLookup.get(route.contributorId) : undefined
    return {
      ...route,
      contributorName: route.contributorName?.trim() || lookup?.name,
      contributorEmail: route.contributorEmail?.trim() || lookup?.email,
    }
  })
}

export async function updateRouteStatus(routeId: string, status: 'approved' | 'rejected', reviewerUid: string) {
  await updateDoc(doc(db, 'routes', routeId), {
    approvalStatus: status,
    status,
    reviewedBy: reviewerUid,
    reviewedAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  })
}

export async function deleteRoute(routeId: string) {
  await deleteDoc(doc(db, 'routes', routeId))
}

export async function getPosts(): Promise<PostItem[]> {
  const docs = await getDocsWithCreatedAtFallback(postsCol)
  return docs.map(mapPostDoc)
}

export async function updatePostStatus(postId: string, status: 'approved' | 'rejected' | 'flagged', moderatorUid: string) {
  const nextStatus = status === 'flagged' ? 'pending' : status
  await updateDoc(doc(db, 'posts', postId), {
    moderationStatus: nextStatus,
    isFlagged: status === 'flagged',
    moderatedBy: moderatorUid,
    moderatedAt: serverTimestamp(),
  })
}

export async function deletePost(postId: string) {
  await deleteDoc(doc(db, 'posts', postId))
}

export async function getFeedback(): Promise<FeedbackItem[]> {
  const docs = await getDocsWithCreatedAtFallback(feedbackCol)
  return docs.map((d) => {
    const data = d.data()
    return {
      id: d.id,
      type: data.type ?? 'feedback',
      status: data.status ?? 'pending',
      message: data.message ?? data.content ?? '',
      reason: getFeedbackReason(data),
      postId: data.postId ?? data.targetPostId ?? data.targetId,
      createdAt: normalizeTimestamp(data.createdAt ?? data.timestamp),
      userId: data.userId,
    }
  })
}

export async function updateFeedbackStatus(feedbackId: string, status: 'resolved' | 'dismissed') {
  await updateDoc(doc(db, 'feedbacks', feedbackId), { status, updatedAt: serverTimestamp() })
}

export async function deleteFeedback(feedbackId: string) {
  await deleteDoc(doc(db, 'feedbacks', feedbackId))
}

export async function getAnnouncements(): Promise<AnnouncementItem[]> {
  const docs = await getDocsWithCreatedAtFallback(announcementsCol)
  return docs.map((d) => {
    const data = d.data() as Omit<AnnouncementItem, 'id'> & Record<string, unknown>
    return {
      id: d.id,
      ...data,
      createdAt: normalizeTimestamp(data.createdAt),
      scheduledAt: normalizeTimestamp(data.scheduledAt),
      expiresAt: normalizeTimestamp(data.expiresAt),
    }
  })
}

export async function createAnnouncement(payload: Omit<AnnouncementItem, 'id' | 'createdAt'>) {
  await addDoc(announcementsCol, {
    ...payload,
    createdAt: serverTimestamp(),
  })
}

export async function updateAnnouncement(id: string, payload: Partial<AnnouncementItem>) {
  await updateDoc(doc(db, 'announcements', id), payload)
}

export async function deleteAnnouncement(id: string) {
  await deleteDoc(doc(db, 'announcements', id))
}

export async function getDashboardStats(): Promise<DashboardStats> {
  const [users, routes, posts] = await Promise.all([getUsers(), getRoutes(), getPosts()])
  const feedbackDocs = await getDocsWithCreatedAtFallback(feedbackCol)
  return buildDashboardStatsFromData(users, routes, posts, feedbackDocs)
}

export function subscribeDashboardStats(
  onData: (stats: DashboardStats) => void,
  onError?: (error: Error) => void,
) {
  let users: AppUser[] = []
  let routes: RouteItem[] = []
  let posts: PostItem[] = []
  let feedbackDocs: QueryDocumentSnapshot<DocumentData>[] = []

  let usersReady = false
  let routesReady = false
  let postsReady = false
  let feedbackReady = false

  const emitIfReady = () => {
    if (!usersReady || !routesReady || !postsReady || !feedbackReady) return
    onData(buildDashboardStatsFromData(users, routes, posts, feedbackDocs))
  }

  const handleError = (err: unknown) => {
    onError?.(err instanceof Error ? err : new Error('Failed to stream dashboard data'))
  }

  const unsubUsers = subscribeWithTimestampFallback(
    usersCol,
    (docs) => {
      usersReady = true
      users = sortDocsByCreatedAtDesc([...docs]).map(mapUserDoc)
      emitIfReady()
    },
    handleError,
  )

  const unsubRoutes = subscribeWithTimestampFallback(
    routesCol,
    (docs) => {
      routesReady = true
      routes = sortDocsByCreatedAtDesc([...docs]).map(mapRouteDoc)
      emitIfReady()
    },
    handleError,
  )

  const unsubPosts = subscribeWithTimestampFallback(
    postsCol,
    (docs) => {
      postsReady = true
      posts = sortDocsByCreatedAtDesc([...docs]).map(mapPostDoc)
      emitIfReady()
    },
    handleError,
  )

  const unsubFeedback = subscribeWithTimestampFallback(
    feedbackCol,
    (docs) => {
      feedbackReady = true
      feedbackDocs = sortDocsByCreatedAtDesc([...docs])
      emitIfReady()
    },
    handleError,
  )

  return () => {
    unsubUsers()
    unsubRoutes()
    unsubPosts()
    unsubFeedback()
  }
}

export async function getModeratorStats() {
  const users = await getUsers()
  const moderators = users.filter((u) => u.role === 'moderator')

  const [routeApprovedSnap, postModeratedSnap] = await Promise.all([
    getDocs(query(routesCol, where('status', '==', 'approved'))),
    getDocs(query(postsCol, where('moderationStatus', 'in', ['approved', 'rejected', 'flagged']))),
  ])

  const approvedRoutesByModerator = new Map<string, number>()
  routeApprovedSnap.forEach((d) => {
    const reviewer = d.data().reviewedBy
    if (reviewer) {
      approvedRoutesByModerator.set(reviewer, (approvedRoutesByModerator.get(reviewer) ?? 0) + 1)
    }
  })

  const moderatedPostsByModerator = new Map<string, number>()
  postModeratedSnap.forEach((d) => {
    const moderator = d.data().moderatedBy
    if (moderator) {
      moderatedPostsByModerator.set(moderator, (moderatedPostsByModerator.get(moderator) ?? 0) + 1)
    }
  })

  return moderators.map((m) => ({
    ...m,
    routesApproved: approvedRoutesByModerator.get(m.id) ?? 0,
    postsModerated: moderatedPostsByModerator.get(m.id) ?? 0,
  }))
}
