'use client'

import { useState, useEffect } from 'react'
import { guardLogin, getGuardStatus, guardFieldCheckIn, guardFieldCheckOut } from '@/app/actions/guard'

export default function GuardTerminal() {
    const [authMode, setAuthMode] = useState<'login' | 'terminal'>('login')
    const [guard, setGuard] = useState<any>(null)
    const [status, setStatus] = useState<any>(null)
    const [loading, setLoading] = useState(false)
    const [currentTime, setCurrentTime] = useState(new Date())

    // Update time every second
    useEffect(() => {
        const interval = setInterval(() => setCurrentTime(new Date()), 1000)
        return () => clearInterval(interval)
    }, [])

    // Load guard status after login
    useEffect(() => {
        if (guard) {
            loadStatus()
            const interval = setInterval(loadStatus, 10000) // Refresh every 10s
            return () => clearInterval(interval)
        }
    }, [guard])

    async function loadStatus() {
        if (!guard) return
        try {
            const data = await getGuardStatus(guard.id)
            setStatus(data)
        } catch (error) {
            console.error('Status error:', error)
        }
    }

    async function handleCheckIn() {
        if (!guard || !guard.primary_unit_id) {
            alert('No primary unit assigned')
            return
        }

        setLoading(true)
        try {
            const result = await guardFieldCheckIn(guard.id, guard.primary_unit_id)
            if (result.success) {
                loadStatus()
            } else {
                alert(result.error || 'Check-in failed')
            }
        } catch (error: any) {
            alert(error.message || 'Check-in failed')
        } finally {
            setLoading(false)
        }
    }

    async function handleCheckOut() {
        setLoading(true)
        try {
            const result = await guardFieldCheckOut(guard.id)
            if (result.success) {
                loadStatus()
            } else {
                alert(result.error || 'Check-out failed')
            }
        } catch (error: any) {
            alert(error.message || 'Check-out failed')
        } finally {
            setLoading(false)
        }
    }

    function handleLogout() {
        setGuard(null)
        setStatus(null)
        setAuthMode('login')
    }

    if (authMode === 'login') {
        return <LoginScreen onSuccess={(guardData) => {
            setGuard(guardData)
            setAuthMode('terminal')
        }} />
    }

    return (
        <div className="min-h-screen bg-slate-900 flex items-center justify-center p-4">
            <div className="w-full max-w-md">
                {/* Header */}
                <div className="bg-slate-800 border-2 border-slate-700 rounded-t-2xl p-6 text-center">
                    <h1 className="text-3xl font-bold text-white mb-2">{guard.full_name}</h1>
                    <p className="text-xl text-slate-300 mb-1">{guard.guard_code}</p>
                    <p className="text-lg text-slate-400">{guard.primary_unit_name}</p>
                </div>

                {/* Time Display */}
                <div className="bg-slate-800 border-x-2 border-slate-700 p-8 text-center">
                    <div className="text-6xl font-bold text-green-400 font-mono">
                        {currentTime.toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false })}
                    </div>
                    <div className="text-xl text-slate-400 mt-2">
                        {currentTime.toLocaleDateString('en-IN', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' })}
                    </div>
                </div>

                {/* Status/Action */}
                <div className="bg-slate-800 border-2 border-slate-700 rounded-b-2xl p-6">
                    {status?.isCheckedIn ? (
                        <>
                            <div className="mb-6 text-center">
                                <div className="inline-flex items-center gap-2 px-6 py-3 bg-green-500/20 border-2 border-green-500 rounded-full">
                                    <div className="w-3 h-3 bg-green-500 rounded-full animate-pulse"></div>
                                    <span className="text-xl font-bold text-green-400">ON DUTY</span>
                                </div>
                                <p className="text-slate-400 mt-4 text-lg">
                                    Since {new Date(status.checkInTime).toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit' })}
                                </p>
                                <p className="text-slate-500 text-sm">{status.workingUnit}</p>
                            </div>
                            <button
                                onClick={handleCheckOut}
                                disabled={loading}
                                className="w-full py-8 bg-red-600 hover:bg-red-700 disabled:opacity-50 text-white rounded-2xl text-3xl font-bold transition shadow-lg"
                            >
                                {loading ? 'CHECKING OUT...' : 'CHECK OUT'}
                            </button>
                        </>
                    ) : (
                        <>
                            <div className="mb-6 text-center">
                                <div className="inline-flex items-center gap-2 px-6 py-3 bg-slate-700 border-2 border-slate-600 rounded-full">
                                    <div className="w-3 h-3 bg-slate-500 rounded-full"></div>
                                    <span className="text-xl font-bold text-slate-400">OFF DUTY</span>
                                </div>
                            </div>
                            <button
                                onClick={handleCheckIn}
                                disabled={loading}
                                className="w-full py-8 bg-green-600 hover:bg-green-700 disabled:opacity-50 text-white rounded-2xl text-3xl font-bold transition shadow-lg"
                            >
                                {loading ? 'CHECKING IN...' : 'CHECK IN'}
                            </button>
                        </>
                    )}

                    <button
                        onClick={handleLogout}
                        className="w-full mt-4 py-4 bg-slate-700 hover:bg-slate-600 text-slate-300 rounded-lg text-lg font-semibold transition"
                    >
                        Logout
                    </button>
                </div>
            </div>
        </div>
    )
}

function LoginScreen({ onSuccess }: { onSuccess: (guard: any) => void }) {
    const [guardCode, setGuardCode] = useState('')
    const [otp, setOtp] = useState('')
    const [loading, setLoading] = useState(false)

    async function handleLogin(e: React.FormEvent) {
        e.preventDefault()
        setLoading(true)

        try {
            const result = await guardLogin(guardCode, otp)
            if (result.success && result.guard) {
                onSuccess(result.guard)
            } else {
                alert(result.error || 'Login failed')
            }
        } catch (error: any) {
            alert(error.message || 'Login failed')
        } finally {
            setLoading(false)
        }
    }

    return (
        <div className="min-h-screen bg-slate-900 flex items-center justify-center p-4">
            <div className="w-full max-w-md">
                <div className="bg-slate-800 border-2 border-slate-700 rounded-2xl p-8">
                    <h1 className="text-4xl font-bold text-white mb-2 text-center">Guard Terminal</h1>
                    <p className="text-slate-400 text-center mb-8">Check In / Check Out</p>

                    <form onSubmit={handleLogin} className="space-y-6">
                        <div>
                            <label className="block text-lg font-semibold text-slate-300 mb-3">Guard Code</label>
                            <input
                                type="text"
                                required
                                value={guardCode}
                                onChange={(e) => setGuardCode(e.target.value.toUpperCase())}
                                placeholder="GRD001"
                                className="w-full px-6 py-5 bg-slate-700 border-2 border-slate-600 rounded-xl text-white text-2xl font-mono text-center focus:outline-none focus:ring-4 focus:ring-blue-500 focus:border-blue-500"
                                autoComplete="off"
                            />
                        </div>

                        <div>
                            <label className="block text-lg font-semibold text-slate-300 mb-3">OTP</label>
                            <input
                                type="text"
                                required
                                inputMode="numeric"
                                pattern="[0-9]{4}"
                                maxLength={4}
                                value={otp}
                                onChange={(e) => setOtp(e.target.value.replace(/\D/g, ''))}
                                placeholder="••••"
                                className="w-full px-6 py-5 bg-slate-700 border-2 border-slate-600 rounded-xl text-white text-4xl font-mono text-center tracking-widest focus:outline-none focus:ring-4 focus:ring-blue-500 focus:border-blue-500"
                                autoComplete="off"
                            />
                        </div>

                        <button
                            type="submit"
                            disabled={loading || guardCode.length < 3 || otp.length !== 4}
                            className="w-full py-6 bg-blue-600 hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed text-white rounded-xl text-2xl font-bold transition shadow-lg"
                        >
                            {loading ? 'LOGGING IN...' : 'LOGIN'}
                        </button>
                    </form>

                    <p className="text-slate-500 text-sm text-center mt-6">
                        Use guard code + 4-digit OTP
                    </p>
                </div>
            </div>
        </div>
    )
}
