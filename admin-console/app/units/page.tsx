'use client'

import { useState, useEffect } from 'react'
import { getUnits, createUnit, deleteUnit } from '@/app/actions/workforce'
import type { Unit } from '@/types/database'

export default function UnitsPage() {
    const [units, setUnits] = useState<Unit[]>([])
    const [loading, setLoading] = useState(true)
    const [showAddForm, setShowAddForm] = useState(false)

    useEffect(() => {
        loadData()
    }, [])

    async function loadData() {
        setLoading(true)
        try {
            const data = await getUnits()
            setUnits(data as Unit[])
        } catch (error) {
            console.error('Error loading units:', error)
        } finally {
            setLoading(false)
        }
    }

    async function handleDelete(id: string) {
        if (!confirm('Archive this unit?')) return

        try {
            await deleteUnit(id)
            loadData()
        } catch (error) {
            console.error('Error deleting unit:', error)
            alert('Failed to delete unit')
        }
    }

    return (
        <div className="min-h-screen bg-navy-900 p-8">
            <div className="flex justify-between items-center mb-8">
                <div>
                    <h1 className="text-3xl font-bold text-white">Units</h1>
                    <p className="text-slate-400 mt-1">Manage sites and locations</p>
                </div>
                <button
                    onClick={() => setShowAddForm(true)}
                    className="px-6 py-3 bg-blue-600 hover:bg-blue-700 text-white rounded-lg font-semibold transition"
                >
                    + Add Unit
                </button>
            </div>

            <div className="bg-slate-800 border border-slate-700 rounded-lg overflow-hidden">
                <table className="w-full">
                    <thead className="bg-slate-700">
                        <tr>
                            <th className="px-6 py-4 text-left text-sm font-semibold text-slate-300">Unit Name</th>
                            <th className="px-6 py-4 text-left text-sm font-semibold text-slate-300">Address</th>
                            <th className="px-6 py-4 text-left text-sm font-semibold text-slate-300">Required Guards</th>
                            <th className="px-6 py-4 text-left text-sm font-semibold text-slate-300">Created</th>
                            <th className="px-6 py-4 text-right text-sm font-semibold text-slate-300">Actions</th>
                        </tr>
                    </thead>
                    <tbody>
                        {loading ? (
                            <tr>
                                <td colSpan={5} className="px-6 py-12 text-center text-slate-400">Loading...</td>
                            </tr>
                        ) : units.length === 0 ? (
                            <tr>
                                <td colSpan={5} className="px-6 py-12 text-center text-slate-400">
                                    No units found. Click "Add Unit" to create one.
                                </td>
                            </tr>
                        ) : (
                            units.map((unit) => (
                                <tr key={unit.id} className="border-t border-slate-700 hover:bg-slate-700/50 transition">
                                    <td className="px-6 py-4 text-white font-semibold">{unit.unit_name}</td>
                                    <td className="px-6 py-4 text-slate-300">{unit.address || '—'}</td>
                                    <td className="px-6 py-4 text-slate-300">{unit.required_guard_count}</td>
                                    <td className="px-6 py-4 text-slate-400">
                                        {new Date(unit.created_at).toLocaleDateString()}
                                    </td>
                                    <td className="px-6 py-4 text-right">
                                        <button
                                            onClick={() => handleDelete(unit.id)}
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
            </div>

            {showAddForm && (
                <AddUnitForm
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

function AddUnitForm({ onClose, onSuccess }: {
    onClose: () => void
    onSuccess: () => void
}) {
    const [formData, setFormData] = useState({
        unit_name: '',
        address: '',
        required_guard_count: 1
    })
    const [submitting, setSubmitting] = useState(false)

    async function handleSubmit(e: React.FormEvent) {
        e.preventDefault()
        setSubmitting(true)

        try {
            await createUnit(formData)
            onSuccess()
        } catch (error) {
            console.error('Error creating unit:', error)
            alert('Failed to create unit')
        } finally {
            setSubmitting(false)
        }
    }

    return (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
            <div className="bg-slate-800 border border-slate-700 rounded-lg p-8 max-w-md w-full">
                <h2 className="text-2xl font-bold text-white mb-6">Add Unit</h2>

                <form onSubmit={handleSubmit} className="space-y-4">
                    <div>
                        <label className="block text-sm font-medium text-slate-300 mb-2">Unit Name *</label>
                        <input
                            type="text"
                            required
                            value={formData.unit_name}
                            onChange={(e) => setFormData({ ...formData, unit_name: e.target.value })}
                            className="w-full px-4 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                        />
                    </div>

                    <div>
                        <label className="block text-sm font-medium text-slate-300 mb-2">Address</label>
                        <textarea
                            value={formData.address}
                            onChange={(e) => setFormData({ ...formData, address: e.target.value })}
                            rows={3}
                            className="w-full px-4 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                        />
                    </div>

                    <div>
                        <label className="block text-sm font-medium text-slate-300 mb-2">Required Guard Count *</label>
                        <input
                            type="number"
                            required
                            min="1"
                            value={formData.required_guard_count}
                            onChange={(e) => setFormData({ ...formData, required_guard_count: parseInt(e.target.value) })}
                            className="w-full px-4 py-2 bg-slate-700 border border-slate-600 rounded-lg text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                        />
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
                            {submitting ? 'Creating...' : 'Create Unit'}
                        </button>
                    </div>
                </form>
            </div>
        </div>
    )
}
