import {
  Timestamp,
  addDoc,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  orderBy,
  query,
  serverTimestamp,
  updateDoc,
  where,
  type QueryDocumentSnapshot,
  type DocumentData,
} from 'firebase/firestore'
import { db } from '@/lib/firebase'
import type {
  AnnouncementItem,
  AppUser,
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
  try {
    return await getDocs(query(colRef, orderBy('createdAt', 'desc')))
  } catch {
    return await getDocs(colRef)
  }
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

function toDateLabel(ts?: Timestamp) {
  if (!ts) return 'Unknown'
  return ts.toDate().toLocaleDateString('en-PH', { month: 'short', day: 'numeric' })
}

function toWeekLabel(ts?: Timestamp) {
  if (!ts) return 'Unknown'
  const d = ts.toDate()
  const start = new Date(d)
  start.setDate(d.getDate() - d.getDay())
  return `${start.toLocaleDateString('en-PH', { month: 'short', day: 'numeric' })}`
}

export async function getCurrentUserRole(uid: string): Promise<UserRole | null> {
  const userSnap = await getDoc(doc(db, 'users', uid))
  if (!userSnap.exists()) return null
  const role = (userSnap.data().role ?? 'user') as UserRole
  return role
}

export async function getUsers(): Promise<AppUser[]> {
  const snap = await getDocsWithCreatedAtFallback(usersCol)
  const docs = sortDocsByCreatedAtDesc([...snap.docs])
  return docs.map((d) => {
    const data = d.data()
    return {
      id: d.id,
      name: data.displayName ?? data.name ?? data.userName ?? 'Unknown User',
      email: data.email ?? '',
      role: data.role ?? 'user',
      status: data.isBanned ? 'banned' : (data.status ?? 'active'),
      createdAt: normalizeTimestamp(data.createdAt ?? data.timestamp),
      routesContributed: data.routesContributed ?? data.contributionCount ?? 0,
      badges: data.badges ?? [],
      achievements: data.achievements ?? [],
      streakDays: data.streakDays ?? 0,
      contributionCount: data.contributionCount ?? 0,
      userCategory: data.userCategory ?? 'all',
    } as AppUser
  })
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
  await deleteDoc(doc(db, 'users', userId))
}

export async function getRoutes(): Promise<RouteItem[]> {
  const snap = await getDocsWithCreatedAtFallback(routesCol)
  const docs = sortDocsByCreatedAtDesc([...snap.docs])
  return docs.map((d) => {
    const data = d.data()
    return {
      id: d.id,
      startLocation: data.startLocation ?? data.from ?? 'Unknown',
      endLocation: data.endLocation ?? data.to ?? 'Unknown',
      contributorId: data.contributorId ?? data.userId ?? '',
      contributorName: data.contributorName ?? data.userName,
      createdAt: normalizeTimestamp(data.createdAt ?? data.timestamp),
      status: data.approvalStatus ?? data.status ?? 'pending',
      views: data.views ?? 0,
      upvotes: data.upvotes ?? 0,
      downvotes: data.downvotes ?? 0,
      steps: data.steps ?? [],
      transportModes: data.transportModes ?? [],
      etaMinutes: data.etaMinutes,
      fareEstimate: data.fareEstimate,
      distanceKm: data.distanceKm,
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
  const snap = await getDocsWithCreatedAtFallback(postsCol)
  const docs = sortDocsByCreatedAtDesc([...snap.docs])
  return docs.map((d) => {
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
  })
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
  const snap = await getDocsWithCreatedAtFallback(feedbackCol)
  const docs = sortDocsByCreatedAtDesc([...snap.docs])
  return docs.map((d) => {
    const data = d.data()
    return {
      id: d.id,
      type: data.type ?? 'feedback',
      status: data.status ?? 'pending',
      message: data.message ?? data.content ?? '',
      reason: data.reason,
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
  const snap = await getDocsWithCreatedAtFallback(announcementsCol)
  const docs = sortDocsByCreatedAtDesc([...snap.docs])
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

  const userGrowthMap = new Map<string, number>()
  users.forEach((u) => {
    const key = toDateLabel(u.createdAt)
    userGrowthMap.set(key, (userGrowthMap.get(key) ?? 0) + 1)
  })

  const routesWeeklyMap = new Map<string, number>()
  routes.forEach((r) => {
    const key = toWeekLabel(r.createdAt)
    routesWeeklyMap.set(key, (routesWeeklyMap.get(key) ?? 0) + 1)
  })

  const recentUsers = users.slice(0, 4).map((u) => ({
    id: `u-${u.id}`,
    type: 'signup',
    description: `${u.name} signed up`,
    time: toDateLabel(u.createdAt),
  }))

  const recentRoutes = routes.slice(0, 4).map((r) => ({
    id: `r-${r.id}`,
    type: 'route',
    description: `Route submitted: ${r.startLocation} to ${r.endLocation}`,
    time: toDateLabel(r.createdAt),
  }))

  const feedbackSnap = await getDocsWithCreatedAtFallback(feedbackCol)
  const recentReports = sortDocsByCreatedAtDesc([...feedbackSnap.docs]).slice(0, 4).map((f) => ({
    id: `f-${f.id}`,
    type: 'report',
    description: `Reported content: ${f.data().reason ?? 'No reason provided'}`,
    time: toDateLabel(f.data().createdAt),
  }))

  return {
    totalUsers: users.length,
    activeUsers: users.filter((u) => u.status !== 'banned').length,
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
    userGrowth: Array.from(userGrowthMap.entries()).map(([label, count]) => ({ label, count })).slice(-8),
    routesPerWeek: Array.from(routesWeeklyMap.entries()).map(([label, count]) => ({ label, count })).slice(-8),
    recentActivity: [...recentUsers, ...recentRoutes, ...recentReports].slice(0, 10),
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
