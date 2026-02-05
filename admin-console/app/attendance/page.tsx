'use client'

import { useState, useEffect } from 'react'
import {
    getActiveShifts,
    getPendingApprovals,
    getTodayAttendanceMetrics,
    guardCheckIn,
    guardCheckOut,
    approveWorkEvent,
    rejectWorkEvent
} from '@/app/actions/attendance'
import { getUnits, getGuards } from '@/app/actions/workforce'

export default function AttendancePage() {
    const [activeShifts, setActiveShifts] = useState<any[]>([])
    const [pendingApprovals, setPendingApprovals] = useState<any[]>([])
    const [metrics, setMetrics] = useState({ onDuty: 0, pendingApprovals: 0, anomalies: 0 })
    const [loading, setLoading] = useState(true)
    const [showCheckInForm, setShowCheckInForm] = useState(false)
    const [units, setUnits] = useState<any[]>([])
    const [guards, setGuards] = useState<any[]>([])

    useEffect(() => {
        loadData()
        // Refresh every 30 seconds
        const interval = setInterval(loadData, 30000)
        return () => clearInterval(interval)
    }, [])

    async function loadData() {
        setLoading(true)
        try {
            const [shiftsData, approvalsData, metricsData, unitsData, guardsData] = await Promise.all([
                getActiveShifts(),
                getPendingApprovals(),
                getTodayAttendanceMetrics(),
                getUnits(),
                getGuards({})
            ])

            setActiveShifts(shiftsData)
            setPendingApprovals(approvalsData)
            setMetrics(metricsData)
            setUnits(unitsData)
            setGuards(guardsData.guards)
        } catch (error) {
            console.error('Error loading attendance:', error)
        } finally {
            setLoading(false)
        }
    }

    async function handleApprove(eventId: string) {
        try {
            const result = await approveWorkEvent(eventId, 'admin') // TODO: Real user ID
            if (result.success) {
                loadData()
            } else {
                alert(result.error)
            }
        } catch (error) {
            console.error('Error approving:', error)
        }
    }

    async function handleReject(eventId: string) {
        if (!confirm('Reject this work event?')) return

        try {
            const result = await rejectWorkEvent(eventId, 'admin')
            if (result.success) {
                loadData()
            } else {
                alert(result.error)
            }
        } catch (error) {
            console.error('Error rejecting:', error)
        }
    }

    async function handleCheckOut(guardId: string) {
        if (!confirm('Check out this guard?')) return

        try {
            const result = await guardCheckOut({ guard_id: guardId })
            if (result.success) {
                loadData()
            } else {
                alert(result.error)
            }
        } catch (error) {
            console.error('Error checking out:', error)
        }
    }

    return (
        <div className="min-h-screen bg-navy-900 p-8">
            {/* Header */}
            <div className="flex justify-between items-center mb-8">
                <div>
                    <h1 className="text-3xl font-bold text-white">Attendance Command Center</h1>
                    <p className="text-slate-400 mt-1">Real-time work event management</p>
                </div>
                <div className="flex items-center gap-4">
                    <div className="flex items-center gap-2">
                        <div className="w-2 h-2 bg-green-500 rounded-full animate-pulse"></div>
                        <span className="text-sm text-slate-400">Live</span>
                    </div>
                    <button
                        onClick={() => setShowCheckInForm(true)}
                        className="px-6 py-3 bg-blue-600 hover:bg-blue-700 text-white rounded-lg font-semibold transition"
                    >
                        + Manual Check-In
                    </button>
                </div>
            </div>

            {/* Metrics */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
                <MetricCard label="On Duty Now" value={metrics.onDuty} variant="success" />
                <MetricCard label="Pending Approvals" value={metrics.pendingApprovals} variant={metrics.pendingApprovals > 0 ? "warning" : "neutral"} />
                <MetricCard label="Anomalies Today" value={metrics.anomalies} variant={metrics.anomalies > 0 ? "error" : "neutral"} />
            </div>

            {/* Pending Approvals (Critical - Top) */}
            {pendingApprovals.length > 0 && (
                <div className="mb-8">
                    <h2 className="text-xl font-bold text-white mb-4">⚠️ Pending Approvals</h2>
                    <div className="bg-amber-900/20 border border-amber-600 rounded-lg overflow-hidden">
                        <table className="w-full">
                            <thead className="bg-amber-900/30">
                                <tr>
                                    <th className="px-6 py-3 text-left text-sm font-semibold text-amber-200">Guard</th>
                                    <th className="px-6 py-3 text-left text-sm font-semibold text-amber-200">Primary Unit</th>
                                    <th className="px-6 py-3 text-left text-sm font-semibold text-amber-200">Working Unit</th>
                                    <th className="px-6 py-3 text-left text-sm font-semibold text-amber-200">Duty Type</th>
                                    <th className="px-6 py-3 text-left text-sm font-semibold text-amber-200">Check-In</th>
                                    <th className="px-6 py-3 text-left text-sm font-semibold text-amber-200">Anomaly</th>
                                    <th className="px-6 py-3 text-right text-sm font-semibold text-amber-200">Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                                {pendingApprovals.map((event) => (
                                    <tr key={event.id} className="border-t border-amber-600/30">
                                        <td className="px-6 py-4 text-white font-medium">
                                            {event.guard?.full_name}
                                            <span className="block text-xs text-slate-400">{event.guard?.guard_code}</span>
                                        </td>
                                        <td className="px-6 py-4 text-slate-300">{event.primary_unit?.unit_name}</td>
                                        <td className="px-6 py-4 text-white font-semibold">{event.working_unit?.unit_name}</td>
                                        <td className="px-6 py-4">
                                            <DutyTypeBadge type={event.duty_type} />
                                        </td>
                                        <td className="px-6 py-4 text-slate-300">
                                            {new Date(event.check_in_time).toLocaleTimeString()}
                                        </td>
                                        <td className="px-6 py-4">
                                            {event.anomaly_flag ? (
                                                <span className="text-xs text-amber-400">{event.anomaly_reason}</span>
                                            ) : '—'}
                                        </td>
                                        <td className="px-6 py-4 text-right">
                                            <div className="flex gap-2 justify-end">
                                                <button
                                                    onClick={() => handleApprove(event.id)}
                                                    className="px-4 py-2 bg-green-600 hover:bg-green-700 text-white rounded text-sm font-semibold"
                                                >
                                                    Approve
                                                </button>
                                                <button
                                                    onClick={() => handleReject(event.id)}
                                                    className="px-4 py-2 bg-red-600 hover:bg-red-700 text-white rounded text-sm font-semibold"
                                                >
                                                    Reject
                                                </button>
                                            </div>
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                </div>
            )}

            {/* Active Shifts */}
            <div>
                <h2 className="text-xl font-bold text-white mb-4">Active Shifts ({activeShifts.length})</h2>
                <div className="bg-slate-800 border border-slate-700 rounded-lg overflow-hidden">
                    <table className="w-full">
                        <thead className="bg-slate-700">
                            <tr>
                                <th className="px-6 py-3 text-left text-sm font-semibold text-slate-300">Guard</th>
                                <th className="px-6 py-3 text-left text-sm font-semibold text-slate-300">Unit</th>
                                <th className="px-6 py-3 text-left text-sm font-semibold text-slate-300">Duty Type</th>
                                <th className="px-6 py-3 text-left text-sm font-semibold text-slate-300">Check-In</th>
                                <th className="px-6 py-3 text-left text-sm font-semibold text-slate-300">Duration</th>
                                <th className="px-6 py-3 text-left text-sm font-semibold text-slate-300">Status</th>
                                <th className="px-6 py-3 text-right text-sm font-semibold text-slate-300">Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            {loading ? (
                                <tr>
                                    <td colSpan={7} className="px-6 py-12 text-center text-slate-400">Loading...</td>
                                </tr>
                            ) : activeShifts.length === 0 ? (
                                <tr>
                                    <td colSpan={7} className="px-6 py-12 text-center text-slate-400">No active shifts</td>
                                </tr>
                            ) : (
                                activeShifts.map((shift) => (
                                    <tr key={shift.id} className="border-t border-slate-700 hover:bg-slate-700/50 transition">
                                        <td className="px-6 py-4 text-white font-medium">
                                            {shift.guard?.full_name}
                                            <span className="block text-xs text-slate-400">{shift.guard?.guard_code}</span>
                                        </td>
                                        <td className="px-6 py-4 text-slate-300">{shift.working_unit?.unit_name}</td>
                                        <td className="px-6 py-4">
                                            <DutyTypeBadge type={shift.duty_type} />
                                        </td>
                                        <td className="px-6 py-4 text-slate-300">
                                            {new Date(shift.check_in_time).toLocaleTimeString()}
                                        </td>
                                        <td className="px-6 py-4 text-slate-300">
                                            <LiveDuration checkInTime={shift.check_in_time} />
                                        </td>
                                        <td className="px-6 py-4">
                                            <ApprovalBadge status={shift.approval_status} />
                                        </td>
                                        <td className="px-6 py-4 text-right">
                                            <button
                                                onClick={() => handleCheckOut(shift.guard_id)}
                                                className="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded text-sm font-semibold"
                                            >
                                                Check Out
                                            </button>
                                        </td>
                                    </tr>
                                ))
                            )}
                        </tbody>
                    </table>
                </div>
            </div>

            {/* Check-In Form */}
            {showCheckInForm && (
                <CheckInForm
                    guards={guards}
                    units={units}
                    onClose={() => setShowCheckInForm(false)}
                    onSuccess={() => {
                        setShowCheckInForm(false)
                        loadData()
                    }}
                />
            )}
        </div>
    )
}

function MetricCard({ label, value, variant = 'neutral' }: {
    label: string
    value: number
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
            <p className={`text-4xl font-bold ${valueColors[variant]}`}>{value}</p>
        </div>
    )
}

function DutyTypeBadge({ type }: { type: string }) {
    const colors: Record<string, string> = {
        PRIMARY: 'bg-blue-500/20 text-blue-400 border-blue-500/50',
        TEMP_DEPLOYMENT: 'bg-purple-500/20 text-purple-400 border-purple-500/50',
        OVERTIME: 'bg-orange-500/20 text-orange-400 border-orange-500/50',
        DOUBLE_SHIFT: 'bg-red-500/20 text-red-400 border-red-500/50',
        UNSCHEDULED: 'bg-amber-500/20 text-amber-400 border-amber-500/50'
    }

    return (
        <span className={`px-3 py-1 rounded-full text-xs font-semibold border ${colors[type] || colors.UNSCHEDULED}`}>
            {type.replace('_', ' ')}
        </span>
    )
}

function ApprovalBadge({ status }: { status: string }) {
    const colors: Record<string, string> = {
        AUTO_APPROVED: 'bg-green-500/20 text-green-400 border-green-500/50',
        PENDING: 'bg-amber-500/20 text-amber-400 border-amber-500/50',
        APPROVED: 'bg-green-500/20 text-green-400 border-green-500/50',
        REJECTED: 'bg-red-500/20 text-red-400 border-red-500/50'
    }

    return (
        <span className={`px-3 py-1 rounded-full text-xs font-semibold border ${colors[status]}`}>
            {status.replace('_', ' ')}
        </span>
    )
}

function LiveDuration({ checkInTime }: { checkInTime: string }) {
    const [duration, setDuration] = useState('')

    useEffect(() => {
        const update = () => {
            const start = new Date(checkInTime)
            const now = new Date()
            const hours = Math.floor((now.getTime() - start.getTime()) / (1000 * 60 * 60))
            const minutes = Math.floor(((now.getTime() - start.getTime()) % (1000 * 60 * 60)) / (1000 * 60))
            setDuration(`${hours}h ${minutes}m`)
        }

        update()
        const interval = setInterval(update, 60000) // Update every minute
        return () => clearInterval(interval)
    }, [checkInTime])

    return <span>{duration}</span>
}

function CheckInForm({ guards, units, onClose, onSuccess }: {
    guards: any[]
    units: any[]
    onClose: () => void
    onSuccess: () => void
}) {
    const [guardId, setGuardId] = useState('')
    const [workingUnitId, setWorkingUnitId] = useState('')
    const [submitting, setSubmitting] = useState(false)

    async function handleSubmit(e: React.FormEvent) {
        e.preventDefault()
        setSubmitting(true)

        try {
            const result = await guardCheckIn({
                guard_id: guardId,
                working_unit_id: workingUnitId,
                created_by: 'admin' // TODO: Real user ID
            })

            if (result.success) {
                alert(result.message)
                onSuccess()
            } else {
                alert(result.error)
            }
        } catch (error: any) {
            alert(error.message || 'Check-in failed')
        } finally {
            setSubmitting(false)
        }
    }

    return (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
            <div className="bg-slate-800 border border-slate-700 rounded-lg p-8 max-w-md w-full">
                <h2 className="text-2xl font-bold text-white mb-6">Manual Check-In</h2>

                <form onSubmit={handleSubmit} className="space-y-4">
                    <div>
                        <label className="block text-sm font-medium text-slate-300 mb-2">Guard *</label>
                        <select
                            required
                            value={guardId}
                            onChange={(e) => setGuardId(e.target.value)}
                            className="w-full px-4 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                        >
                            <option value="">Select guard...</option>
                            {guards.filter(g => g.employment_status === 'active').map(guard => (
                                <option key={guard.id} value={guard.id}>
                                    {guard.full_name} ({guard.guard_code})
                                </option>
                            ))}
                        </select>
                    </div>

                    <div>
                        <label className="block text-sm font-medium text-slate-300 mb-2">Working Unit *</label>
                        <select
                            required
                            value={workingUnitId}
                            onChange={(e) => setWorkingUnitId(e.target.value)}
                            className="w-full px-4 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                        >
                            <option value="">Select unit...</option>
                            {units.map(unit => (
                                <option key={unit.id} value={unit.id}>{unit.unit_name}</option>
                            ))}
                        </select>
                    </div>

                    <div className="flex gap-4 pt-4">
                        <button
                            type="button"
                            onClick={onClose}
                            className="flex-1 px-6 py-3 bg-slate-700 hover:bg-slate-600 text-white rounded-lg font-semibold transition"
                        >
                            Cancel
                        </button>
                        <button
                            type="submit"
                            disabled={submitting}
                            className="flex-1 px-6 py-3 bg-blue-600 hover:bg-blue-700 disabled:opacity-50 text-white rounded-lg font-semibold transition"
                        >
                            {submitting ? 'Checking In...' : 'Check In'}
                        </button>
                    </div>
                </form>
            </div>
        </div>
    )
}
