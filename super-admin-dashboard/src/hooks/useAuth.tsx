import type { ReactNode } from 'react'
import { createContext, useContext, useEffect, useMemo, useState } from 'react'
import {
  signInWithEmailAndPassword,
  signOut,
  onAuthStateChanged,
  type User,
} from 'firebase/auth'
import { auth } from '@/lib/firebase'
import { getCurrentUserAccess } from '@/lib/firestoreApi'

interface AuthContextValue {
  user: User | null
  role: string | null
  isLoading: boolean
  login: (email: string, password: string) => Promise<void>
  logout: () => Promise<void>
  isSuperAdmin: boolean
  // True when access comes from a temporary grant, not the superadmin role.
  isTempSuperAdmin: boolean
  tempSuperadminUntil: Date | null
}

const AuthContext = createContext<AuthContextValue | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null)
  const [role, setRole] = useState<string | null>(null)
  const [tempSuperadminUntil, setTempSuperadminUntil] = useState<Date | null>(null)
  const [isLoading, setIsLoading] = useState(true)

  useEffect(() => {
    const unsub = onAuthStateChanged(auth, async (nextUser) => {
      setUser(nextUser)
      if (!nextUser) {
        setRole(null)
        setTempSuperadminUntil(null)
        setIsLoading(false)
        return
      }

      const access = await getCurrentUserAccess(nextUser.uid)
      setRole(access?.role ?? null)
      setTempSuperadminUntil(access?.tempSuperadminUntil ?? null)
      setIsLoading(false)
    })

    return () => unsub()
  }, [])

  // Sign a temporary superadmin out the moment their access runs out.
  useEffect(() => {
    if (!tempSuperadminUntil || role === 'superadmin') return
    const timer = setTimeout(() => {
      setTempSuperadminUntil(null)
      void signOut(auth)
    }, Math.max(0, tempSuperadminUntil.getTime() - Date.now()))
    return () => clearTimeout(timer)
  }, [role, tempSuperadminUntil])

  const isTempSuperAdmin = role !== 'superadmin' && tempSuperadminUntil !== null

  const value = useMemo(
    () => ({
      user,
      role,
      isLoading,
      isSuperAdmin: role === 'superadmin' || isTempSuperAdmin,
      isTempSuperAdmin,
      tempSuperadminUntil,
      login: async (email: string, password: string) => {
        setIsLoading(true)
        await signInWithEmailAndPassword(auth, email, password)
      },
      logout: async () => {
        await signOut(auth)
      },
    }),
    [isLoading, isTempSuperAdmin, role, tempSuperadminUntil, user],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const ctx = useContext(AuthContext)
  if (!ctx) {
    throw new Error('useAuth must be used inside AuthProvider')
  }
  return ctx
}
