import Link from 'next/link'

export default function SelectRolePage() {
    const roles = [
        {
            title: 'Platform Admin',
            description: 'Manage the entire platform and all organizations',
            icon: (
                <svg className="w-12 h-12" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                </svg>
            ),
            href: '/login',
            color: 'from-purple-600 to-purple-400',
            hoverColor: 'hover:border-purple-600'
        },
        {
            title: 'Organization Admin',
            description: 'Manage your organization, guards, and units',
            icon: (
                <svg className="w-12 h-12" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4" />
                </svg>
            ),
            href: '/login',
            color: 'from-blue-600 to-blue-400',
            hoverColor: 'hover:border-blue-600'
        },
        {
            title: 'Supervisor',
            description: 'Manage your unit and mark attendance for guards',
            icon: (
                <svg className="w-12 h-12" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
                </svg>
            ),
            href: '/guard/login',
            color: 'from-green-600 to-green-400',
            hoverColor: 'hover:border-green-600'
        },
        {
            title: 'Security Guard',
            description: 'Mark attendance and manage your profile',
            icon: (
                <svg className="w-12 h-12" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                </svg>
            ),
            href: '/guard/login',
            color: 'from-orange-600 to-orange-400',
            hoverColor: 'hover:border-orange-600'
        }
    ]

    return (
        <div className="min-h-screen bg-gradient-to-br from-blue-950 via-neutral-950 to-neutral-900 flex items-center justify-center p-6">
            <div className="w-full max-w-6xl">
                {/* Header */}
                <div className="text-center mb-12">
                    <Link href="/" className="inline-flex items-center gap-2 mb-6 text-neutral-400 hover:text-white transition-colors">
                        <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 19l-7-7m0 0l7-7m-7 7h18" />
                        </svg>
                        Back to Home
                    </Link>

                    <h1 className="text-5xl font-bold text-white mb-4">Select Your Role</h1>
                    <p className="text-xl text-neutral-400">Choose how you want to sign in to Voylox</p>
                </div>

                {/* Role Cards Grid */}
                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                    {roles.map((role) => (
                        <Link
                            key={role.title}
                            href={role.href}
                            className={`group bg-neutral-900/80 backdrop-blur-sm border-2 border-neutral-800 rounded-2xl p-8 transition-all hover:scale-105 ${role.hoverColor}`}
                        >
                            <div className="flex flex-col items-center text-center">
                                {/* Icon */}
                                <div className={`w-24 h-24 rounded-2xl bg-gradient-to-br ${role.color} bg-opacity-20 flex items-center justify-center mb-6 group-hover:scale-110 transition-transform`}>
                                    <div className={`text-transparent bg-gradient-to-br ${role.color} bg-clip-text`}>
                                        {role.icon}
                                    </div>
                                </div>

                                {/* Title */}
                                <h2 className="text-2xl font-bold text-white mb-3">{role.title}</h2>

                                {/* Description */}
                                <p className="text-neutral-400 mb-6">{role.description}</p>

                                {/* Button */}
                                <div className={`px-6 py-3 rounded-lg bg-gradient-to-r ${role.color} text-white font-semibold flex items-center gap-2 group-hover:gap-3 transition-all`}>
                                    Sign In
                                    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 7l5 5m0 0l-5 5m5-5H6" />
                                    </svg>
                                </div>
                            </div>
                        </Link>
                    ))}
                </div>

                {/* Footer Note */}
                <div className="mt-12 text-center">
                    <p className="text-neutral-500 text-sm">
                        Don't have an account?{' '}
                        <Link href="/signup" className="text-blue-400 hover:text-blue-300 font-semibold">
                            Sign up for free
                        </Link>
                    </p>
                </div>
            </div>
        </div>
    )
}
