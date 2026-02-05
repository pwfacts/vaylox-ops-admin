'use client'

import { useState } from 'react'
import { login } from '@/app/actions/auth'
import { useRouter } from 'next/navigation'

export default function LoginPage() {
    const router = useRouter()
    const [formData, setFormData] = useState({
        email: '',
        password: ''
    })
    const [submitting, setSubmitting] = useState(false)
    const [error, setError] = useState('')

    async function handleSubmit(e: React.FormEvent) {
        e.preventDefault()
        setError('')
        setSubmitting(true)

        try {
            const result = await login(formData.email, formData.password)

            if (!result.success) {
                setError(result.error || 'Login failed')
            } else {
                // Redirect to dashboard
                router.push('/')
                router.refresh()
            }
        } catch (err: any) {
            setError(err.message || 'An error occurred')
        } finally {
            setSubmitting(false)
        }
    }

    return (
        <div className="min-h-screen bg-neutral-950 flex items-center justify-center p-4">
            <div className="w-full max-w-md">
                {/* Header */}
                <div className="text-center mb-8">
                    <h1 className="text-4xl font-bold text-white mb-2">
                        Welcome Back
                    </h1>
                    <p className="text-neutral-400">
                        Sign in to your workforce management dashboard
                    </p>
                </div>

                {/* Login Form */}
                <div className="bg-neutral-900 border border-neutral-800 rounded-lg p-8">
                    <form onSubmit={handleSubmit} className="space-y-6">
                        <div>
                            <label className="block text-sm font-medium text-neutral-300 mb-1">
                                Email
                            </label>
                            <input
                                type="email"
                                value={formData.email}
                                onChange={(e) => setFormData({ ...formData, email: e.target.value })}
                                required
                                placeholder="you@company.com"
                                className="w-full px-4 py-3 bg-neutral-800 border border-neutral-700 rounded-lg text-white placeholder-neutral-500 focus:outline-none focus:border-blue-500"
                            />
                        </div>

                        <div>
                            <label className="block text-sm font-medium text-neutral-300 mb-1">
                                Password
                            </label>
                            <input
                                type="password"
                                value={formData.password}
                                onChange={(e) => setFormData({ ...formData, password: e.target.value })}
                                required
                                placeholder="••••••••"
                                className="w-full px-4 py-3 bg-neutral-800 border border-neutral-700 rounded-lg text-white placeholder-neutral-500 focus:outline-none focus:border-blue-500"
                            />
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
                            {submitting ? 'Signing In...' : 'Sign In'}
                        </button>

                        {/* Signup Link */}
                        <p className="text-center text-neutral-400 text-sm">
                            Don't have an account?{' '}
                            <a href="/signup" className="text-blue-400 hover:text-blue-300">
                                Start free trial
                            </a>
                        </p>
                    </form>
                </div>

                {/* Platform Admin Link */}
                <div className="mt-6 text-center">
                    <a href="/platform" className="text-neutral-500 hover:text-neutral-400 text-sm">
                        Platform Admin Access →
                    </a>
                </div>
            </div>
        </div>
    )
}
