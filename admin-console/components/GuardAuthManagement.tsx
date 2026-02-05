'use client'

import { useState } from 'react'
import { createGuardAccount, resetGuardPassword, linkGuardGoogleAccount } from '@/app/actions/guard-auth'

interface GuardAuthManagementProps {
    guard: {
        id: string
        full_name: string
        email?: string
        user_id?: string
        auth_provider?: string
        google_id?: string
    }
    onUpdate: () => void
}

export default function GuardAuthManagement({ guard, onUpdate }: GuardAuthManagementProps) {
    const [showPasswordForm, setShowPasswordForm] = useState(false)
    const [showCreateForm, setShowCreateForm] = useState(false)
    const [showGoogleLink, setShowGoogleLink] = useState(false)
    const [loading, setLoading] = useState(false)
    const [error, setError] = useState('')
    const [success, setSuccess] = useState('')

    const [createFormData, setCreateFormData] = useState({
        email: guard.email || '',
        password: ''
    })

    const [resetFormData, setResetFormData] = useState({
        new_password: ''
    })

    const [googleFormData, setGoogleFormData] = useState({
        google_email: '',
        google_id: ''
    })

    async function handleCreateAccount(e: React.FormEvent) {
        e.preventDefault()
        setError('')
        setSuccess('')
        setLoading(true)

        try {
            const result = await createGuardAccount({
                guard_id: guard.id,
                email: createFormData.email,
                password: createFormData.password,
                created_by: 'CURRENT_ADMIN_ID' // TODO: Get from session
            })

            if (!result.success) {
                setError(result.error || 'Failed to create account')
            } else {
                setSuccess('Account created successfully!')
                setShowCreateForm(false)
                setCreateFormData({ email: '', password: '' })
                onUpdate()
            }
        } catch (err: any) {
            setError(err.message)
        } finally {
            setLoading(false)
        }
    }

    async function handleResetPassword(e: React.FormEvent) {
        e.preventDefault()
        setError('')
        setSuccess('')
        setLoading(true)

        try {
            const result = await resetGuardPassword({
                guard_id: guard.id,
                new_password: resetFormData.new_password,
                reset_by: 'CURRENT_ADMIN_ID' // TODO: Get from session
            })

            if (!result.success) {
                setError(result.error || 'Failed to reset password')
            } else {
                setSuccess(result.message || 'Password reset successfully!')
                setShowPasswordForm(false)
                setResetFormData({ new_password: '' })
            }
        } catch (err: any) {
            setError(err.message)
        } finally {
            setLoading(false)
        }
    }

    async function handleLinkGoogle(e: React.FormEvent) {
        e.preventDefault()
        setError('')
        setSuccess('')
        setLoading(true)

        try {
            const result = await linkGuardGoogleAccount({
                guard_id: guard.id,
                google_email: googleFormData.google_email,
                google_id: googleFormData.google_id
            })

            if (!result.success) {
                setError(result.error || 'Failed to link Google account')
            } else {
                setSuccess('Google account linked successfully!')
                setShowGoogleLink(false)
                setGoogleFormData({ google_email: '', google_id: '' })
                onUpdate()
            }
        } catch (err: any) {
            setError(err.message)
        } finally {
            setLoading(false)
        }
    }

    return (
        <div className="space-y-4">
            {/* Status Display */}
            <div className="bg-neutral-800/50 rounded-lg p-4">
                <h3 className="text-white font-semibold mb-2">Authentication Status</h3>
                <div className="space-y-2 text-sm">
                    <div className="flex justify-between">
                        <span className="text-neutral-400">Account Status:</span>
                        <span className={guard.user_id ? 'text-green-400' : 'text-red-400'}>
                            {guard.user_id ? '✓ Account Created' : '✗ No Account'}
                        </span>
                    </div>
                    <div className="flex justify-between">
                        <span className="text-neutral-400">Auth Provider:</span>
                        <span className="text-white">
                            {guard.auth_ ? guard.auth_provider.toUpperCase() : 'N/A'}
                        </span>
                    </div>
                    {guard.email && (
                        <div className="flex justify-between">
                            <span className="text-neutral-400">Email:</span>
                            <span className="text-white">{guard.email}</span>
                        </div>
                    )}
                </div>
            </div>

            {/* Messages */}
            {error && (
                <div className="bg-red-900/20 border border-red-800 rounded-lg p-3">
                    <p className="text-red-400 text-sm">{error}</p>
                </div>
            )}
            {success && (
                <div className="bg-green-900/20 border border-green-800 rounded-lg p-3">
                    <p className="text-green-400 text-sm">{success}</p>
                </div>
            )}

            {/* Actions */}
            <div className="space-y-2">
                {!guard.user_id ? (
                    // No account - show create button
                    <>
                        {!showCreateForm ? (
                            <button
                                onClick={() => setShowCreateForm(true)}
                                className="w-full px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
                            >
                                Create Guard Account
                            </button>
                        ) : (
                            <form onSubmit={handleCreateAccount} className="space-y-3 p-4 bg-neutral-800/30 rounded-lg">
                                <div>
                                    <label className="block text-sm text-neutral-300 mb-1">Email</label>
                                    <input
                                        type="email"
                                        value={createFormData.email}
                                        onChange={(e) => setCreateFormData({ ...createFormData, email: e.target.value })}
                                        required
                                        className="w-full px-3 py-2 bg-neutral-800 border border-neutral-700 rounded text-white text-sm"
                                    />
                                </div>
                                <div>
                                    <label className="block text-sm text-neutral-300 mb-1">Password</label>
                                    <input
                                        type="password"
                                        value={createFormData.password}
                                        onChange={(e) => setCreateFormData({ ...createFormData, password: e.target.value })}
                                        required
                                        minLength={8}
                                        className="w-full px-3 py-2 bg-neutral-800 border border-neutral-700 rounded text-white text-sm"
                                    />
                                    <p className="text-xs text-neutral-500 mt-1">Min 8 characters</p>
                                </div>
                                <div className="flex gap-2">
                                    <button
                                        type="submit"
                                        disabled={loading}
                                        className="flex-1 px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 transition-colors disabled:opacity-50 text-sm"
                                    >
                                        {loading ? 'Creating...' : 'Create Account'}
                                    </button>
                                    <button
                                        type="button"
                                        onClick={() => setShowCreateForm(false)}
                                        className="px-4 py-2 bg-neutral-700 text-white rounded hover:bg-neutral-600 transition-colors text-sm"
                                    >
                                        Cancel
                                    </button>
                                </div>
                            </form>
                        )}
                    </>
                ) : (
                    // Account exists - show reset and Google link
                    <>
                        {!showPasswordForm ? (
                            <button
                                onClick={() => setShowPasswordForm(true)}
                                className="w-full px-4 py-2 bg-yellow-600 text-white rounded-lg hover:bg-yellow-700 transition-colors"
                            >
                                Reset Password
                            </button>
                        ) : (
                            <form onSubmit={handleResetPassword} className="space-y-3 p-4 bg-neutral-800/30 rounded-lg">
                                <div>
                                    <label className="block text-sm text-neutral-300 mb-1">New Password</label>
                                    <input
                                        type="password"
                                        value={resetFormData.new_password}
                                        onChange={(e) => setResetFormData({ new_password: e.target.value })}
                                        required
                                        minLength={8}
                                        className="w-full px-3 py-2 bg-neutral-800 border border-neutral-700 rounded text-white text-sm"
                                    />
                                </div>
                                <div className="flex gap-2">
                                    <button
                                        type="submit"
                                        disabled={loading}
                                        className="flex-1 px-4 py-2 bg-yellow-600 text-white rounded hover:bg-yellow-700 transition-colors disabled:opacity-50 text-sm"
                                    >
                                        {loading ? 'Resetting...' : 'Reset Password'}
                                    </button>
                                    <button
                                        type="button"
                                        onClick={() => setShowPasswordForm(false)}
                                        className="px-4 py-2 bg-neutral-700 text-white rounded hover:bg-neutral-600 transition-colors text-sm"
                                    >
                                        Cancel
                                    </button>
                                </div>
                            </form>
                        )}

                        {!guard.google_id && (
                            <>
                                {!showGoogleLink ? (
                                    <button
                                        onClick={() => setShowGoogleLink(true)}
                                        className="w-full px-4 py-2 bg-white text-neutral-900 rounded-lg hover:bg-neutral-100 transition-colors flex items-center justify-center gap-2"
                                    >
                                        <svg className="w-4 h-4" viewBox="0 0 24 24">
                                            <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" />
                                            <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" />
                                            <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" />
                                            <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" />
                                        </svg>
                                        Link Google Account
                                    </button>
                                ) : (
                                    <form onSubmit={handleLinkGoogle} className="space-y-3 p-4 bg-neutral-800/30 rounded-lg">
                                        <div>
                                            <label className="block text-sm text-neutral-300 mb-1">Google Email</label>
                                            <input
                                                type="email"
                                                value={googleFormData.google_email}
                                                onChange={(e) => setGoogleFormData({ ...googleFormData, google_email: e.target.value })}
                                                required
                                                className="w-full px-3 py-2 bg-neutral-800 border border-neutral-700 rounded text-white text-sm"
                                            />
                                        </div>
                                        <div>
                                            <label className="block text-sm text-neutral-300 mb-1">Google ID</label>
                                            <input
                                                type="text"
                                                value={googleFormData.google_id}
                                                onChange={(e) => setGoogleFormData({ ...googleFormData, google_id: e.target.value })}
                                                required
                                                className="w-full px-3 py-2 bg-neutral-800 border border-neutral-700 rounded text-white text-sm"
                                            />
                                            <p className="text-xs text-neutral-500 mt-1">Get from guard after first Google login attempt</p>
                                        </div>
                                        <div className="flex gap-2">
                                            <button
                                                type="submit"
                                                disabled={loading}
                                                className="flex-1 px-4 py-2 bg-white text-neutral-900 rounded hover:bg-neutral-100 transition-colors disabled:opacity-50 text-sm"
                                            >
                                                {loading ? 'Linking...' : 'Link Account'}
                                            </button>
                                            <button
                                                type="button"
                                                onClick={() => setShowGoogleLink(false)}
                                                className="px-4 py-2 bg-neutral-700 text-white rounded hover:bg-neutral-600 transition-colors text-sm"
                                            >
                                                Cancel
                                            </button>
                                        </div>
                                    </form>
                                )}
                            </>
                        )}
                    </>
                )}
            </div>
        </div>
    )
}
