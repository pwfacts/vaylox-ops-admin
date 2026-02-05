'use client'

import { useEffect, useState } from 'react'
import { getDashboardMetrics } from '@/app/actions/workforce'
import { getTodayAttendanceMetrics } from '@/app/actions/attendance'

interface DashboardMetrics {
  activeGuards: number
  understaffedSites: number
  onDuty: number
  pendingApprovals: number
  anomalies: number
}

export default function CommandDashboard() {
  const [metrics, setMetrics] = useState<DashboardMetrics>({
    activeGuards: 0,
    understaffedSites: 0,
    onDuty: 0,
    pendingApprovals: 0,
    anomalies: 0
  })
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    loadMetrics()

    // Refresh every 30 seconds
    const interval = setInterval(loadMetrics, 30000)
    return () => clearInterval(interval)
  }, [])

  async function loadMetrics() {
    try {
      const [workforceData, attendanceData] = await Promise.all([
        getDashboardMetrics(),
        getTodayAttendanceMetrics()
      ])

      setMetrics({
        activeGuards: workforceData.activeGuards,
        understaffedSites: workforceData.understaffedSites,
        onDuty: attendanceData.onDuty,
        pendingApprovals: attendanceData.pendingApprovals,
        anomalies: attendanceData.anomalies
      })
    } catch (error) {
      console.error('Error loading metrics:', error)
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen bg-navy-900 p-8 space-y-8">
      {/* Header */}
      <div className="flex justify-between items-center">
        <div>
          <h1 className="text-3xl font-bold text-white">Command Dashboard</h1>
          <p className="text-slate-400 mt-1">Real-time operational overview</p>
        </div>
        <div className="flex items-center gap-2">
          <div className="w-2 h-2 bg-green-500 rounded-full animate-pulse"></div>
          <span className="text-sm text-slate-400">Live</span>
        </div>
      </div>

      {/* Live Metrics */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
        <MetricCard
          label="Active Guards"
          value={metrics.activeGuards}
          loading={loading}
          variant="neutral"
        />
        <MetricCard
          label="On Duty Now"
          value={metrics.onDuty}
          loading={loading}
          variant="success"
        />
        <MetricCard
          label="Pending Approvals"
          value={metrics.pendingApprovals}
          loading={loading}
          variant={metrics.pendingApprovals > 0 ? "warning" : "neutral"}
        />
        <MetricCard
          label="Understaffed Sites"
          value={metrics.understaffedSites}
          loading={loading}
          variant={metrics.understaffedSites > 0 ? "error" : "neutral"}
        />
      </div>

      {/* Quick Actions */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="bg-slate-800 border border-slate-700 rounded-lg p-6">
          <h3 className="text-lg font-semibold text-white mb-4">Quick Actions</h3>
          <div className="space-y-3">
            <ActionButton href="/workforce" icon="👥">Manage Guards</ActionButton>
            <ActionButton href="/units" icon="🏢">Manage Units</ActionButton>
            <ActionButton href="/attendance" icon="✅">View Attendance</ActionButton>
          </div>
        </div>

        <div className="bg-slate-800 border border-slate-700 rounded-lg p-6">
          <h3 className="text-lg font-semibold text-white mb-4">System Status</h3>
          <div className="space-y-3">
            <StatusItem label="Total Guards" value={metrics.activeGuards} />
            <StatusItem label="On Duty" value={metrics.onDuty} />
            <StatusItem label="Pending Approvals" value={metrics.pendingApprovals} critical={metrics.pendingApprovals > 0} />
            <StatusItem label="Understaffed Units" value={metrics.understaffedSites} critical={metrics.understaffedSites > 0} />
          </div>
        </div>
      </div>
    </div>
  )
}

function MetricCard({
  label,
  value,
  loading,
  variant = 'neutral'
}: {
  label: string
  value: number
  loading: boolean
  variant?: 'success' | 'warning' | 'error' | 'neutral'
}) {
  const colors = {
    success: 'border-green-500/50 bg-green-500/10',
    warning: 'border-amber-500/50 bg-amber-500/10',
    error: 'border-red-500/50 bg-red-500/10',
    neutral: 'border-slate-700 bg-slate-800'
  }

  const valueColors = {
    success: 'text-green-400',
    warning: 'text-amber-400',
    error: 'text-red-400',
    neutral: 'text-white'
  }

  return (
    <div className={`border rounded-lg p-6 ${colors[variant]}`}>
      <p className="text-sm text-slate-400 mb-2">{label}</p>
      {loading ? (
        <div className="h-10 bg-slate-700 animate-pulse rounded w-20"></div>
      ) : (
        <p className={`text-4xl font-bold ${valueColors[variant]}`}>{value}</p>
      )}
    </div>
  )
}

function ActionButton({ href, icon, children }: { href: string; icon: string; children: React.ReactNode }) {
  return (
    <a
      href={href}
      className="flex items-center gap-3 p-4 bg-slate-700/50 hover:bg-slate-700 rounded-lg transition group"
    >
      <span className="text-2xl">{icon}</span>
      <span className="text-white group-hover:text-blue-400 font-medium">{children}</span>
      <svg className="w-5 h-5 text-slate-400 group-hover:text-white transition ml-auto" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
      </svg>
    </a>
  )
}

function StatusItem({ label, value, critical }: { label: string; value: number; critical?: boolean }) {
  return (
    <div className="flex justify-between items-center">
      <span className="text-slate-400">{label}</span>
      <span className={`font-bold ${critical ? 'text-red-400' : 'text-white'}`}>{value}</span>
    </div>
  )
}
