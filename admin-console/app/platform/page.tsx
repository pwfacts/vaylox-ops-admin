'use client'

import { useEffect, useState } from 'react'
import {
    getAllOrganizations,
    createOrganization,
    updateOrganization,
    getPlatformMetrics,
    suspendOrganization,
    reactivateOrganization,
    setGuardLimit
} from '@/app/actions/platform'

// ============================================
// TYPES
// ============================================

interface Organization {
    id: string
    name: string
    slug: string
    subscription_status: 'trial' | 'active' | 'suspended' | 'cancelled'
    plan: 'starter' | 'professional' | 'enterprise'
    guard_limit: number
    trial_ends_at?: string
    created_at: string
}

interface PlatformMetrics {
    totalOrganizations: number
    activeOrganizations: number
    suspendedOrganizations: number
    trialOrganizations: number
    totalGuards: number
}

export default function PlatformAdminPage() {
    const [organizations, setOrganizations] = useState<Organization[]>([])
    const [metrics, setMetrics] = useState<PlatformMetrics | null>(null)
    const [loading, setLoading] = useState(true)
    const [showCreateForm, setShowCreateForm] = useState(false)

    useEffect(() => {
        loadData()
    }, [])

    async function loadData() {
        try {
            const [orgsData, metricsData] = await Promise.all([
                getAllOrganizations(),
                getPlatformMetrics()
            ])
            setOrganizations(orgsData as Organization[])
            setMetrics(metricsData)
        } catch (error) {
            console.error('Error loading platform data:', error)
        } finally {
            setLoading(false)
        }
    }

    async function handleSuspend(orgId: string) {
        if (!confirm('Suspend this organization? They will lose access immediately.')) return

        try {
            await suspendOrganization(orgId)
            loadData()
        } catch (error) {
            alert('Failed to suspend organization')
        }
    }

    async function handleReactivate(orgId: string) {
        try {
            await reactivateOrganization(orgId)
            loadData()
        } catch (error) {
            alert('Failed to reactivate organization')
        }
    }

    if (loading) {
        return (
            <div className="p-8 flex items-center justify-center">
                <div className="text-neutral-400">Loading platform data...</div>
            </div>
        )
    }

    return (
        <div className="p-8 space-y-8 max-w-7xl mx-auto">
            {/* Header */}
            <div className="flex justify-between items-center">
                <div>
                    <h1 className="text-3xl font-bold text-white">Platform Admin</h1>
                    <p className="text-neutral-400 mt-1">Multi-tenant organization management</p>
                </div>
                <button
                    onClick={() => setShowCreateForm(true)}
                    className="px-6 py-3 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors font-semibold"
                >
                    + Create Organization
                </button>
            </div>

            {/* Metrics */}
            {metrics && (
                <div className="grid grid-cols-1 md:grid-cols-5 gap-4">
                    <MetricCard
                        label="Total Organizations"
                        value={metrics.totalOrganizations}
                        color="blue"
                    />
                    <MetricCard
                        label="Active"
                        value={metrics.activeOrganizations}
                        color="green"
                    />
                    <MetricCard
                        label="Trial"
                        value={metrics.trialOrganizations}
                        color="amber"
                    />
                    <MetricCard
                        label="Suspended"
                        value={metrics.suspendedOrganizations}
                        color="red"
                    />
                    <MetricCard
                        label="Total Guards"
                        value={metrics.totalGuards}
                        color="purple"
                    />
                </div>
            )}

            {/* Organizations Table */}
            <div className="bg-neutral-900 border border-neutral-800 rounded-lg overflow-hidden">
                <table className="w-full">
                    <thead className="bg-neutral-800">
                        <tr>
                            <th className="px-6 py-4 text-left text-sm font-semibold text-neutral-300">Organization</th>
                            <th className="px-6 py-4 text-left text-sm font-semibold text-neutral-300">Status</th>
                            <th className="px-6 py-4 text-left text-sm font-semibold text-neutral-300">Plan</th>
                            <th className="px-6 py-4 text-left text-sm font-semibold text-neutral-300">Guard Limit</th>
                            <th className="px-6 py-4 text-left text-sm font-semibold text-neutral-300">Created</th>
                            <th className="px-6 py-4 text-right text-sm font-semibold text-neutral-300">Actions</th>
                        </tr>
                    </thead>
                    <tbody>
                        {organizations.map((org) => (
                            <tr key={org.id} className="border-t border-neutral-800 hover:bg-neutral-800/50">
                                <td className="px-6 py-4">
                                    <div>
                                        <div className="font-semibold text-white">{org.name}</div>
                                        <div className="text-sm text-neutral-400">{org.slug}</div>
                                    </div>
                                </td>
                                <td className="px-6 py-4">
                                    <StatusBadge status={org.subscription_status} />
                                </td>
                                <td className="px-6 py-4">
                                    <span className="text-neutral-300 capitalize">{org.plan}</span>
                                </td>
                                <td className="px-6 py-4">
                                    <span className="text-neutral-300">{org.guard_limit}</span>
                                </td>
                                <td className="px-6 py-4">
                                    <span className="text-neutral-400 text-sm">
                                        {new Date(org.created_at).toLocaleDateString()}
                                    </span>
                                </td>
                                <td className="px-6 py-4 text-right space-x-2">
                                    {org.subscription_status === 'active' ? (
                                        <button
                                            onClick={() => handleSuspend(org.id)}
                                            className="px-3 py-1 bg-red-600/20 text-red-400 rounded hover:bg-red-600/30 text-sm"
                                        >
                                            Suspend
                                        </button>
                                    ) : org.subscription_status === 'suspended' ? (
                                        <button
                                            onClick={() => handleReactivate(org.id)}
                                            className="px-3 py-1 bg-green-600/20 text-green-400 rounded hover:bg-green-600/30 text-sm"
                                        >
                                            Reactivate
                                        </button>
                                    ) : null}
                                </td>
                            </tr>
                        ))}
                    </tbody>
                </table>
            </div>

            {/* Create Form Modal */}
            {showCreateForm && (
                <CreateOrgForm
                    onSuccess={() => {
                        setShowCreateForm(false)
                        loadData()
                    }}
                    onCancel={() => setShowCreateForm(false)}
                />
            )}
        </div>
    )
}

// ============================================
// COMPONENTS
// ============================================

function MetricCard({ label, value, color }: { label: string; value: number; color: string }) {
    const colorClasses = {
        blue: 'bg-blue-600/10 text-blue-400 border-blue-600/30',
        green: 'bg-green-600/10 text-green-400 border-green-600/30',
        amber: 'bg-amber-600/10 text-amber-400 border-amber-600/30',
        red: 'bg-red-600/10 text-red-400 border-red-600/30',
        purple: 'bg-purple-600/10 text-purple-400 border-purple-600/30'
    }[color]

    return (
        <div className={`border rounded-lg p-4 ${colorClasses}`}>
            <div className="text-2xl font-bold">{value}</div>
            <div className="text-sm opacity-80 mt-1">{label}</div>
        </div>
    )
}

function StatusBadge({ status }: { status: string }) {
    const config = {
        trial: { bg: 'bg-amber-600/20', text: 'text-amber-400', label: 'Trial' },
        active: { bg: 'bg-green-600/20', text: 'text-green-400', label: 'Active' },
        suspended: { bg: 'bg-red-600/20', text: 'text-red-400', label: 'Suspended' },
        cancelled: { bg: 'bg-neutral-600/20', text: 'text-neutral-400', label: 'Cancelled' }
    }[status] || { bg: 'bg-neutral-600/20', text: 'text-neutral-400', label: status }

    return (
        <span className={`px-3 py-1 rounded-full text-sm font-medium ${config.bg} ${config.text}`}>
            {config.label}
        </span>
    )
}

function CreateOrgForm({ onSuccess, onCancel }: { onSuccess: () => void; onCancel: () => void }) {
    const [formData, setFormData] = useState({
        name: '',
        slug: '',
        plan: 'starter' as 'starter' | 'professional' | 'enterprise',
        guard_limit: 50
    })
    const [submitting, setSubmitting] = useState(false)

    async function handleSubmit(e: React.FormEvent) {
        e.preventDefault()
        setSubmitting(true)

        try {
            await createOrganization(formData)
            onSuccess()
        } catch (error) {
            alert('Failed to create organization. Check if slug is unique.')
        } finally {
            setSubmitting(false)
        }
    }

    return (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center p-4 z-50">
            <div className="bg-neutral-900 border border-neutral-800 rounded-lg p-6 w-full max-w-md">
                <h2 className="text-xl font-bold text-white mb-4">Create Organization</h2>

                <form onSubmit={handleSubmit} className="space-y-4">
                    <div>
                        <label className="block text-sm font-medium text-neutral-300 mb-1">
                            Organization Name
                        </label>
                        <input
                            type="text"
                            value={formData.name}
                            onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                            required
                            className="w-full px-4 py-2 bg-neutral-800 border border-neutral-700 rounded text-white"
                        />
                    </div>

                    <div>
                        <label className="block text-sm font-medium text-neutral-300 mb-1">
                            Slug (URL-friendly)
                        </label>
                        <input
                            type="text"
                            value={formData.slug}
                            onChange={(e) => setFormData({ ...formData, slug: e.target.value })}
                            required
                            className="w-full px-4 py-2 bg-neutral-800 border border-neutral-700 rounded text-white"
                        />
                    </div>

                    <div>
                        <label className="block text-sm font-medium text-neutral-300 mb-1">
                            Plan
                        </label>
                        <select
                            value={formData.plan}
                            onChange={(e) => setFormData({ ...formData, plan: e.target.value as any })}
                            className="w-full px-4 py-2 bg-neutral-800 border border-neutral-700 rounded text-white"
                        >
                            <option value="starter">Starter</option>
                            <option value="professional">Professional</option>
                            <option value="enterprise">Enterprise</option>
                        </select>
                    </div>

                    <div>
                        <label className="block text-sm font-medium text-neutral-300 mb-1">
                            Guard Limit
                        </label>
                        <input
                            type="number"
                            value={formData.guard_limit}
                            onChange={(e) => setFormData({ ...formData, guard_limit: parseInt(e.target.value) })}
                            min="1"
                            required
                            className="w-full px-4 py-2 bg-neutral-800 border border-neutral-700 rounded text-white"
                        />
                    </div>

                    <div className="flex gap-3 pt-4">
                        <button
                            type="button"
                            onClick={onCancel}
                            className="flex-1 px-4 py-2 bg-neutral-800 text-white rounded hover:bg-neutral-700"
                        >
                            Cancel
                        </button>
                        <button
                            type="submit"
                            disabled={submitting}
                            className="flex-1 px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50"
                        >
                            {submitting ? 'Creating...' : 'Create'}
                        </button>
                    </div>
                </form>
            </div>
        </div>
    )
}
