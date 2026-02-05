'use client'

import { useState } from 'react'
import { signupOrganization } from '@/app/actions/auth'
import { useRouter } from 'next/navigation'

export default function SignupPage() {
    const router = useRouter()
    const [formData, setFormData] = useState({
        organizationName: '',
        slug: '',
        adminEmail: '',
        adminPassword: '',
        adminName: '',
        plan: 'starter' as 'starter' | 'professional' | 'enterprise'
    })
    const [submitting, setSubmitting] = useState(false)
    const [error, setError] = useState('')
    const [success, setSuccess] = useState(false)

    // Auto-generate slug from organization name
    function handleOrgNameChange(name: string) {
        setFormData({
            ...formData,
            organizationName: name,
            slug: name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')
        })
    }

    async function handleSubmit(e: React.FormEvent) {
        e.preventDefault()
        setError('')
        setSubmitting(true)

        try {
            const result = await signupOrganization(formData)

            if (!result.success) {
                setError(result.error || 'Signup failed')
            } else {
                setSuccess(true)
                setTimeout(() => {
                    router.push('/login')
                }, 3000)
            }
        } catch (err: any) {
            setError(err.message || 'An error occurred')
        } finally {
            setSubmitting(false)
        }
    }

    if (success) {
        return (
            <div className="min-h-screen bg-neutral-950 flex items-center justify-center p-4">
                <div className="bg-neutral-900 border border-neutral-800 rounded-lg p-8 max-w-md w-full text-center">
                    <div className="text-green-400 text-5xl mb-4">✓</div>
                    <h2 className="text-2xl font-bold text-white mb-2">Organization Created!</h2>
                    <p className="text-neutral-400 mb-4">
                        Check your email to verify your account. Redirecting to login...
                    </p>
                </div>
            </div>
        )
    }

    return (
        <div className="min-h-screen bg-neutral-950 flex items-center justify-center p-4">
            <div className="w-full max-w-2xl">
                {/* Header */}
                <div className="text-center mb-8">
                    <h1 className="text-4xl font-bold text-white mb-2">
                        Start Your Free Trial
                    </h1>
                    <p className="text-neutral-400">
                        30-day trial • No credit card required • Cancel anytime
                    </p>
                </div>

                {/* Signup Form */}
                <div className="bg-neutral-900 border border-neutral-800 rounded-lg p-8">
                    <form onSubmit={handleSubmit} className="space-y-6">
                        {/* Organization Details */}
                        <div className="space-y-4">
                            <h3 className="text-lg font-semibold text-white border-b border-neutral-800 pb-2">
                                Organization Details
                            </h3>

                            <div>
                                <label className="block text-sm font-medium text-neutral-300 mb-1">
                                    Organization Name
                                </label>
                                <input
                                    type="text"
                                    value={formData.organizationName}
                                    onChange={(e) => handleOrgNameChange(e.target.value)}
                                    required
                                    placeholder="e.g., Acme Security Services"
                                    className="w-full px-4 py-3 bg-neutral-800 border border-neutral-700 rounded-lg text-white placeholder-neutral-500 focus:outline-none focus:border-blue-500"
                                />
                            </div>

                            <div>
                                <label className="block text-sm font-medium text-neutral-300 mb-1">
                                    Organization Slug (URL)
                                </label>
                                <div className="flex items-center gap-2">
                                    <span className="text-neutral-500 text-sm">yourapp.com/</span>
                                    <input
                                        type="text"
                                        value={formData.slug}
                                        onChange={(e) => setFormData({ ...formData, slug: e.target.value })}
                                        required
                                        pattern="[a-z0-9-]+"
                                        placeholder="acme-security"
                                        className="flex-1 px-4 py-3 bg-neutral-800 border border-neutral-700 rounded-lg text-white placeholder-neutral-500 focus:outline-none focus:border-blue-500"
                                    />
                                </div>
                                <p className="text-xs text-neutral-500 mt-1">
                                    Lowercase letters, numbers, and hyphens only
                                </p>
                            </div>

                            <div>
                                <label className="block text-sm font-medium text-neutral-300 mb-2">
                                    Plan
                                </label>
                                <div className="grid grid-cols-3 gap-3">
                                    <PlanCard
                                        name="Starter"
                                        guards={50}
                                        price="$49"
                                        selected={formData.plan === 'starter'}
                                        onClick={() => setFormData({ ...formData, plan: 'starter' })}
                                    />
                                    <PlanCard
                                        name="Professional"
                                        guards={200}
                                        price="$149"
                                        selected={formData.plan === 'professional'}
                                        onClick={() => setFormData({ ...formData, plan: 'professional' })}
                                    />
                                    <PlanCard
                                        name="Enterprise"
                                        guards={500}
                                        price="$349"
                                        selected={formData.plan === 'enterprise'}
                                        onClick={() => setFormData({ ...formData, plan: 'enterprise' })}
                                    />
                                </div>
                            </div>
                        </div>

                        {/* Admin User Details */}
                        <div className="space-y-4 pt-4 border-t border-neutral-800">
                            <h3 className="text-lg font-semibold text-white">Admin Account</h3>

                            <div>
                                <label className="block text-sm font-medium text-neutral-300 mb-1">
                                    Your Name
                                </label>
                                <input
                                    type="text"
                                    value={formData.adminName}
                                    onChange={(e) => setFormData({ ...formData, adminName: e.target.value })}
                                    required
                                    placeholder="John Doe"
                                    className="w-full px-4 py-3 bg-neutral-800 border border-neutral-700 rounded-lg text-white placeholder-neutral-500 focus:outline-none focus:border-blue-500"
                                />
                            </div>

                            <div>
                                <label className="block text-sm font-medium text-neutral-300 mb-1">
                                    Email
                                </label>
                                <input
                                    type="email"
                                    value={formData.adminEmail}
                                    onChange={(e) => setFormData({ ...formData, adminEmail: e.target.value })}
                                    required
                                    placeholder="john@acmesecurity.com"
                                    className="w-full px-4 py-3 bg-neutral-800 border border-neutral-700 rounded-lg text-white placeholder-neutral-500 focus:outline-none focus:border-blue-500"
                                />
                            </div>

                            <div>
                                <label className="block text-sm font-medium text-neutral-300 mb-1">
                                    Password
                                </label>
                                <input
                                    type="password"
                                    value={formData.adminPassword}
                                    onChange={(e) => setFormData({ ...formData, adminPassword: e.target.value })}
                                    required
                                    minLength={8}
                                    placeholder="Min. 8 characters"
                                    className="w-full px-4 py-3 bg-neutral-800 border border-neutral-700 rounded-lg text-white placeholder-neutral-500 focus:outline-none focus:border-blue-500"
                                />
                            </div>
                        </div>

                        {/* Error Display */}
                        {error && (
                            <div className="bg-red-900/20 border border-red-800 rounded-lg p-4">
                                <p className="text-red-400 text-sm">{error}</p>
                            </div>
                        )}

                        {/* Submit Button */}
                        <button
                            type="submit"
                            disabled={submitting}
                            className="w-full px-6 py-4 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors font-semibold text-lg disabled:opacity-50 disabled:cursor-not-allowed"
                        >
                            {submitting ? 'Creating Organization...' : 'Start Free Trial →'}
                        </button>

                        {/* Login Link */}
                        <p className="text-center text-neutral-400 text-sm">
                            Already have an account?{' '}
                            <a href="/login" className="text-blue-400 hover:text-blue-300">
                                Sign in
                            </a>
                        </p>
                    </form>
                </div>

                {/* Trust Indicators */}
                <div className="mt-6 text-center text-neutral-500 text-sm">
                    <p>🔒 Secure • 🚀 5-minute setup • 📊 Instant access</p>
                </div>
            </div>
        </div>
    )
}

// ============================================
// PLAN CARD COMPONENT
// ============================================

function PlanCard({
    name,
    guards,
    price,
    selected,
    onClick
}: {
    name: string
    guards: number
    price: string
    selected: boolean
    onClick: () => void
}) {
    return (
        <button
            type="button"
            onClick={onClick}
            className={`p-4 rounded-lg border-2 transition-all text-left ${selected
                    ? 'border-blue-500 bg-blue-600/10'
                    : 'border-neutral-700 bg-neutral-800 hover:border-neutral-600'
                }`}
        >
            <div className="font-semibold text-white mb-1">{name}</div>
            <div className="text-2xl font-bold text-white mb-1">{price}</div>
            <div className="text-sm text-neutral-400">Up to {guards} guards</div>
        </button>
    )
}
