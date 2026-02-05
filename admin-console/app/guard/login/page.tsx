'use client'

import { useState } from 'react'
import { guardLoginWithEmail, getGuardGoogleOAuthUrl } from '@/app/actions/guard-auth'
import { useRouter } from 'next/navigation'
import Image from 'next/image'

export default function GuardLoginPage() {
    const router = useRouter()
    const [loginType, setLoginType] = useState<'email' | 'google'>('email')
    const [formData, setFormData] = useState({
        email: '',
        password: ''
    })
    const [loading, setLoading] = useState(false)
    const [error, setError] = useState('')

    async function handleEmailLogin(e: React.FormEvent) {
        e.preventDefault()
        setError('')
        setLoading(true)

        try {
            const result = await guardLoginWithEmail(formData.email, formData.password)

            if (!result.success) {
                setError(result.error || 'Login failed')
            } else {
                // Redirect to guard dashboard
                router.push('/guard/dashboard')
                router.refresh()
            }
        } catch (err: any) {
            setError(err.message || 'An error occurred')
        } finally {
            setLoading(false)
        }
    }

    async function handleGoogleLogin() {
        setError('')
        setLoading(true)

        try {
            const result = await getGuardGoogleOAuthUrl()

            if (!result.success) {
                setError(result.error || 'Failed to initiate Google login')
            } else if (result.url) {
                window.location.href = result.url
            }
        } catch (err: any) {
            setError(err.message || 'An error occurred')
            setLoading(false)
        }
    }

    return (
        <div className="min-h-screen bg-gradient-to-br from-blue-900 via-neutral-900 to-neutral-950 flex items-center justify-center p-4">
            <div className="w-full max-w-md">
                {/* Logo/Header */}
                <div className="text-center mb-8">
                    <div className="inline-flex items-center justify-center w-20 h-20 rounded-full bg-blue-600 mb-4">
                        <svg className="w-10 h-10 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
                        </svg>
                    </div>
                    <h1 className="text-3xl font-bold text-white mb-2">Guard Portal</h1>
                    <p className="text-neutral-400">Sign in to access your dashboard</p>
                </div>

                {/* Login Card */}
                <div className="bg-neutral-900/80 backdrop-blur-sm border border-neutral-800 rounded-2xl p-8 shadow-2xl">
                    {/* Tab Selector */}
                    <div className="flex gap-2 mb-6 p-1 bg-neutral-800/50 rounded-lg">
                        <button
                            onClick={() => setLoginType('email')}
                            className={`flex-1 py-2 px-4 rounded-md text-sm font-medium transition-all ${loginType === 'email'
                                    ? 'bg-blue-600 text-white shadow-lg'
                                    : 'text-neutral-400 hover:text-white'
                                }`}
                        >
                            Email Login
                        </button>
                        <button
                            onClick={() => setLoginType('google')}
                            className={`flex-1 py-2 px-4 rounded-md text-sm font-medium transition-all ${loginType === 'google'
                                    ? 'bg-blue-600 text-white shadow-lg'
                                    : 'text-neutral-400 hover:text-white'
                                }`}
                        >
                            Google
                        </button>
                    </div>

                    {/* Email Login Form */}
                    {loginType === 'email' && (
                        <form onSubmit={handleEmailLogin} className="space-y-4">
                            <div>
                                <label className="block text-sm font-medium text-neutral-300 mb-2">
                                    Email Address
                                </label>
                                <input
                                    type="email"
                                    value={formData.email}
                                    onChange={(e) => setFormData({ ...formData, email: e.target.value })}
                                    required
                                    placeholder="guard@example.com"
                                    className="w-full px-4 py-3 bg-neutral-800 border border-neutral-700 rounded-lg text-white placeholder-neutral-500 focus:outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20"
                                />
                            </div>

                            <div>
                                <label className="block text-sm font-medium text-neutral-300 mb-2">
                                    Password
                                </label>
                                <input
                                    type="password"
                                    value={formData.password}
                                    onChange={(e) => setFormData({ ...formData, password: e.target.value })}
                                    required
                                    placeholder="••••••••"
                                    className="w-full px-4 py-3 bg-neutral-800 border border-neutral-700 rounded-lg text-white placeholder-neutral-500 focus:outline-none focus:border-blue-500 focus:ring-2 focus:ring-blue-500/20"
                                />
                            </div>

                            {error && (
                                <div className="bg-red-900/20 border border-red-800 rounded-lg p-3">
                                    <p className="text-red-400 text-sm">{error}</p>
                                </div>
                            )}

                            <button
                                type="submit"
                                disabled={loading}
                                className="w-full px-6 py-3 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors font-semibold disabled:opacity-50 disabled:cursor-not-allowed"
                            >
                                {loading ? 'Signing In...' : 'Sign In'}
                            </button>

                            <p className="text-center text-neutral-500 text-sm">
                                Forgot password?{' '}
                                <span className="text-blue-400">Contact your administrator</span>
                            </p>
                        </form>
                    )}

                    {/* Google Login */}
                    {loginType === 'google' && (
                        <div className="space-y-4">
                            <p className="text-neutral-400 text-sm text-center mb-6">
                                Sign in with your Google account to access your guard portal
                            </p>

                            {error && (
                                <div className="bg-red-900/20 border border-red-800 rounded-lg p-3 mb-4">
                                    <p className="text-red-400 text-sm">{error}</p>
                                </div>
                            )}

                            <button
                                onClick={handleGoogleLogin}
                                disabled={loading}
                                className="w-full px-6 py-3 bg-white text-neutral-900 rounded-lg hover:bg-neutral-100 transition-colors font-semibold flex items-center justify-center gap-3 disabled:opacity-50"
                            >
                                <svg className="w-5 h-5" viewBox="0 0 24 24">
                                    <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" />
                                    <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" />
                                    <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" />
                                    <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" />
                                </svg>
                                {loading ? 'Connecting...' : 'Sign in with Google'}
                            </button>

                            <p className="text-center text-neutral-500 text-xs mt-4">
                                Note: Your Google account must be linked by your administrator first
                            </p>
                        </div>
                    )}
                </div>

                {/* Footer */}
                <p className="text-center text-neutral-500 text-sm mt-6">
                    Not a guard?{' '}
                    <a href="/login" className="text-blue-400 hover:text-blue-300">
                        Admin Login
                    </a>
                </p>
            </div>
        </div>
    )
}
