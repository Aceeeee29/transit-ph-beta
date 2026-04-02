import type { Timestamp } from 'firebase/firestore'

export type UserRole = 'user' | 'moderator' | 'superadmin'
export type UserStatus = 'active' | 'offline' | 'banned'
export type RouteStatus = 'pending' | 'approved' | 'rejected'
export type PostStatus = 'pending' | 'approved' | 'flagged' | 'rejected'
export type AnnouncementType = 'info' | 'warning' | 'critical'
export type AudienceType = 'all' | 'student' | 'employee' | 'foreigner' | 'new_to_area'

export interface AppUser {
  id: string
  name: string
  email: string
  role: UserRole
  status: UserStatus
  createdAt?: Timestamp
  routesContributed: number
  badges?: string[]
  achievements?: string[]
  streakDays?: number
  contributionCount?: number
  userCategory?: AudienceType
}

export interface RouteItem {
  id: string
  startLocation: string
  endLocation: string
  contributorId: string
  contributorName?: string
  contributorEmail?: string
  createdAt?: Timestamp
  updatedAt?: Timestamp
  status: RouteStatus
  views: number
  upvotes: number
  downvotes: number
  feedbackSummary?: {
    fareAccurateYes?: number
    fareAccurateNo?: number
    scheduleAccurateYes?: number
    scheduleAccurateNo?: number
    stillOperatingYes?: number
    stillOperatingNo?: number
  }
  steps?: string[]
  transportModes?: string[]
  etaMinutes?: number
  fareEstimate?: number
  distanceKm?: number
}

export interface PostItem {
  id: string
  userId: string
  userName?: string
  userEmail?: string
  category?: string
  content: string
  images?: string[]
  moderationStatus: PostStatus
  isFlagged?: boolean
  createdAt?: Timestamp
}

export interface FeedbackItem {
  id: string
  type: 'feedback' | 'report'
  status: 'pending' | 'resolved' | 'dismissed'
  message: string
  reason?: string
  postId?: string
  createdAt?: Timestamp
  userId?: string
}

export interface AnnouncementItem {
  id: string
  title: string
  message: string
  type: AnnouncementType
  targetAudience: AudienceType
  isActive: boolean
  scheduledAt?: Timestamp
  expiresAt?: Timestamp
  createdAt?: Timestamp
  createdBy?: string
}

export interface DashboardStats {
  totalUsers: number
  activeUsers: number
  bannedUsers: number
  routes: { approved: number; pending: number; rejected: number }
  posts: { approved: number; pending: number; flagged: number }
  userGrowth: Array<{ label: string; count: number }>
  routesPerWeek: Array<{ label: string; count: number }>
  recentActivity: DashboardActivity[]
}

export type DashboardActivityType = 'signup' | 'route' | 'post' | 'report'
export type DashboardActivitySeverity = 'info' | 'warning' | 'critical'

export interface DashboardActivity {
  id: string
  type: DashboardActivityType
  description: string
  time: string
  timestampMs: number
  severity: DashboardActivitySeverity
}
