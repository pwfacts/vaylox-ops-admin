'use client'

import { useState, useEffect } from 'react'
import { getGuards, createGuard, deleteGuard, getUnits } from '@/app/actions/workforce'
import type { Guard, Unit } from '@/types/database'

export default function WorkforcePage() {
    const [guards, setGuards] = useState<Guard[]>([])
    const [units, setUnits] = useState<Unit[]>([])
    const [loading, setLoading] = useState(true)
    const [showAddForm, setShowAddForm] = useState(false)
    const [search, setSearch] = useState('')
    const [filterUnit, setFilterUnit] = useState('')
    const [filterStatus, setFilterStatus] = useState('')
    const [page, setPage] = useState(1)
    const [totalPages, setTotalPages] = useState(1)

    useEffect(() => {
        loadData()
    }, [search, filterUnit, filterStatus, page])

    async function loadData() {
        setLoading(true)
        try {
            const [guardsData, unitsData] = await Promise.all([
                getGuards({ search, unitId: filterUnit, status: filterStatus, page }),
                getUnits()
            ])

            setGuards(guardsData.guards as Guard[])
            setTotalPages(guardsData.totalPages)
            setUnits(unitsData as Unit[])
        } catch (error) {
            console.error('Error loading workforce:', error)
        } finally {
            setLoading(false)
        }
    }

    async function handleDelete(id: string) {
        if (!confirm('Archive this guard? They will be marked as inactive.')) return

        try {
            await deleteGuard(id)
            loadData()
        } catch (error) {
            console.error('Error deleting guard:', error)
            alert('Failed to delete guard')
        }
    }

    return (
        <div className="min-h-screen bg-navy-900 p-8">
            {/* Header */}
            <div className="flex justify-between items-center mb-8">
                <div>
                    <h1 className="text-3xl font-bold text-white">Workforce</h1>
                    <p className="text-slate-400 mt-1">Manage guards and unit assignments</p>
                </div>
                <button
                    onClick={() => setShowAddForm(true)}
                    className="px-6 py-3 bg-blue-600 hover:bg-blue-700 text-white rounded-lg font-semibold transition"
                >
                    + Add Guard
                </button>
            </div>

            {/* Filters */}
            <div className="bg-slate-800 border border-slate-700 rounded-lg p-6 mb-6">
                <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                    <input
                        type="text"
                        placeholder="Search by name, phone, or code..."
                        value={search}
                        onChange={(e) => setSearch(e.target.value)}
                        className="px-4 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500"
                    />
                    <select
                        value={filterUnit}
                        onChange={(e) => setFilterUnit(e.target.value)}
                        className="px-4 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                    >
                        <option value="">All Units</option>
                        {units.map(unit => (
                            <option key={unit.id} value={unit.id}>{unit.unit_name}</option>
                        ))}
                    </select>
                    <select
                        value={filterStatus}
                        onChange={(e) => setFilterStatus(e.target.value)}
                        className="px-4 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                    >
                        <option value="">All Statuses</option>
                        <option value="active">Active</option>
                        <option value="inactive">Inactive</option>
                        <option value="suspended">Suspended</option>
                    </select>
                </div>
            </div>

            {/* Table */}
            <div className="bg-slate-800 border border-slate-700 rounded-lg overflow-hidden">
                <table className="w-full">
                    <thead className="bg-slate-700">
                        <tr>
                            <th className="px-6 py-4 text-left text-sm font-semibold text-slate-300">Guard Code</th>
                            <th className="px-6 py-4 text-left text-sm font-semibold text-slate-300">Name</th>
                            <th className="px-6 py-4 text-left text-sm font-semibold text-slate-300">Phone</th>
                            <th className="px-6 py-4 text-left text-sm font-semibold text-slate-300">Primary Unit</th>
                            <th className="px-6 py-4 text-left text-sm font-semibold text-slate-300">Status</th>
                            <th className="px-6 py-4 text-left text-sm font-semibold text-slate-300">Created</th>
                            <th className="px-6 py-4 text-right text-sm font-semibold text-slate-300">Actions</th>
                        </tr>
                    </thead>
                    <tbody>
                        {loading ? (
                            <tr>
                                <td colSpan={7} className="px-6 py-12 text-center text-slate-400">
                                    Loading...
                                </td>
                            </tr>
                        ) : guards.length === 0 ? (
                            <tr>
                                <td colSpan={7} className="px-6 py-12 text-center text-slate-400">
                                    No guards found. Click "Add Guard" to create one.
                                </td>
                            </tr>
                        ) : (
                            guards.map((guard) => (
                                <tr key={guard.id} className="border-t border-slate-700 hover:bg-slate-700/50 transition">
                                    <td className="px-6 py-4 text-white font-mono">{guard.guard_code}</td>
                                    <td className="px-6 py-4 text-white">{guard.full_name}</td>
                                    <td className="px-6 py-4 text-slate-300">{guard.phone_number}</td>
                                    <td className="px-6 py-4 text-slate-300">
                                        {(guard as any).unit?.unit_name || '—'}
                                    </td>
                                    <td className="px-6 py-4">
                                        <StatusBadge status={guard.employment_status} />
                                    </td>
                                    <td className="px-6 py-4 text-slate-400">
                                        {new Date(guard.created_at).toLocaleDateString()}
                                    </td>
                                    <td className="px-6 py-4 text-right">
                                        <button
                                            onClick={() => handleDelete(guard.id)}
                                            className="text-red-400 hover:text-red-300 text-sm font-medium"
                                        >
                                            Archive
                                        </button>
                                    </td>
                                </tr>
                            ))
                        )}
                    </tbody>
                </table>

                {/* Pagination */}
                {totalPages > 1 && (
                    <div className="px-6 py-4 border-t border-slate-700 flex justify-between items-center">
                        <button
                            disabled={page === 1}
                            onClick={() => setPage(page - 1)}
                            className="px-4 py-2 bg-slate-700 hover:bg-slate-600 disabled:opacity-50 disabled:cursor-not-allowed text-white rounded text-sm"
                        >
                            Previous
                        </button>
                        <span className="text-slate-400 text-sm">
                            Page {page} of {totalPages}
                        </span>
                        <button
                            disabled={page === totalPages}
                            onClick={() => setPage(page + 1)}
                            className="px-4 py-2 bg-slate-700 hover:bg-slate-600 disabled:opacity-50 disabled:cursor-not-allowed text-white rounded text-sm"
                        >
                            Next
                        </button>
                    </div>
                )}
            </div>

            {/* Add Guard Modal */}
            {showAddForm && (
                <AddGuardForm
                    units={units}
                    onClose={() => setShowAddForm(false)}
                    onSuccess={() => {
                        setShowAddForm(false)
                        loadData()
                    }}
                />
            )}
        </div>
    )
}

function StatusBadge({ status }: { status: string }) {
    const colors = {
        active: 'bg-green-500/20 text-green-400 border-green-500/50',
        inactive: 'bg-slate-500/20 text-slate-400 border-slate-500/50',
        suspended: 'bg-red-500/20 text-red-400 border-red-500/50'
    }

    return (
        <span className={`px-3 py-1 rounded-full text-xs font-semibold border ${colors[status as keyof typeof colors] || colors.inactive}`}>
            {status.charAt(0).toUpperCase() + status.slice(1)}
        </span>
    )
}

function AddGuardForm({ units, onClose, onSuccess }: {
    units: Unit[]
    onClose: () => void
    onSuccess: () => void
}) {
    const [formData, setFormData] = useState({
        full_name: '',
        phone_number: '',
        guard_code: '',
        primary_unit_id: '',
        employment_status: 'active' as 'active' | 'inactive' | 'suspended'
    })
    const [submitting, setSubmitting] = useState(false)

    async function handleSubmit(e: React.FormEvent) {
        e.preventDefault()
        setSubmitting(true)

        try {
            await createGuard(formData)
            onSuccess()
        } catch (error) {
            console.error('Error creating guard:', error)
            alert('Failed to create guard. Check if guard code is unique.')
        } finally {
            setSubmitting(false)
        }
    }

    return (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
            <div className="bg-slate-800 border border-slate-700 rounded-lg p-8 max-w-md w-full">
                <h2 className="text-2xl font-bold text-white mb-6">Add Guard</h2>

                <form onSubmit={handleSubmit} className="space-y-4">
                    <div>
                        <label className="block text-sm font-medium text-slate-300 mb-2">Full Name *</label>
                        <input
                            type="text"
                            required
                            value={formData.full_name}
                            onChange={(e) => setFormData({ ...formData, full_name: e.target.value })}
                            className="w-full px-4 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                        />
                    </div>

                    <div>
                        <label className="block text-sm font-medium text-slate-300 mb-2">Phone Number *</label>
                        <input
                            type="tel"
                            required
                            value={formData.phone_number}
                            onChange={(e) => setFormData({ ...formData, phone_number: e.target.value })}
                            className="w-full px-4 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                        />
                    </div>

                    <div>
                        <label className="block text-sm font-medium text-slate-300 mb-2">Guard Code *</label>
                        <input
                            type="text"
                            required
                            value={formData.guard_code}
                            onChange={(e) => setFormData({ ...formData, guard_code: e.target.value.toUpperCase() })}
                            className="w-full px-4 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white font-mono focus:outline-none focus:ring-2 focus:ring-blue-500"
                            placeholder="e.g. GRD001"
                        />
                    </div>

                    <div>
                        <label className="block text-sm font-medium text-slate-300 mb-2">Primary Unit</label>
                        <select
                            value={formData.primary_unit_id}
                            onChange={(e) => setFormData({ ...formData, primary_unit_id: e.target.value })}
                            className="w-full px-4 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                        >
                            <option value="">Unassigned</option>
                            {units.map(unit => (
                                <option key={unit.id} value={unit.id}>{unit.unit_name}</option>
                            ))}
                        </select>
                    </div>

                    <div>
                        <label className="block text-sm font-medium text-slate-300 mb-2">Status</label>
                        <select
                            value={formData.employment_status}
                            onChange={(e) => setFormData({ ...formData, employment_status: e.target.value as any })}
                            className="w-full px-4 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                        >
                            <option value="active">Active</option>
                            <option value="inactive">Inactive</option>
                            <option value="suspended">Suspended</option>
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
                            {submitting ? 'Creating...' : 'Create Guard'}
                        </button>
                    </div>
                </form>
            </div>
        </div>
    )
}
