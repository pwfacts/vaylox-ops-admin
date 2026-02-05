import Link from 'next/link'
import Image from 'next/image'

export default function LandingPage() {
    return (
        <div className="min-h-screen bg-gradient-to-br from-blue-950 via-neutral-950 to-neutral-900">
            {/* Navbar */}
            <nav className="fixed top-0 left-0 right-0 z-50 bg-neutral-900/80 backdrop-blur-lg border-b border-neutral-800">
                <div className="max-w-7xl mx-auto px-6 py-4">
                    <div className="flex items-center justify-between">
                        {/* Logo */}
                        <div className="flex items-center gap-3">
                            <div className="w-10 h-10 rounded-lg bg-gradient-to-br from-blue-600 to-blue-400 flex items-center justify-center">
                                <svg className="w-6 h-6 text-white" fill="currentColor" viewBox="0 0 24 24">
                                    <path d="M12 2L2 7v10c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V7l-10-5z" />
                                </svg>
                            </div>
                            <div>
                                <h1 className="text-xl font-bold text-white">Voylox</h1>
                                <p className="text-xs text-neutral-400">Security Management</p>
                            </div>
                        </div>

                        {/* Nav Links */}
                        <div className="hidden md:flex items-center gap-8">
                            <a href="#features" className="text-neutral-300 hover:text-white transition-colors">Features</a>
                            <a href="#solutions" className="text-neutral-300 hover:text-white transition-colors">Solutions</a>
                            <a href="#pricing" className="text-neutral-300 hover:text-white transition-colors">Pricing</a>
                            <a href="#contact" className="text-neutral-300 hover:text-white transition-colors">Contact</a>
                        </div>

                        {/* Login Button */}
                        <Link
                            href="/select-role"
                            className="px-6 py-2.5 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors font-semibold"
                        >
                            Login
                        </Link>
                    </div>
                </div>
            </nav>

            {/* Hero Section */}
            <section className="pt-32 pb-20 px-6">
                <div className="max-w-7xl mx-auto">
                    <div className="text-center max-w-4xl mx-auto">
                        <h1 className="text-6xl md:text-7xl font-bold text-white mb-6 leading-tight">
                            Modern Security
                            <span className="block bg-gradient-to-r from-blue-400 to-cyan-400 bg-clip-text text-transparent">
                                Workforce Management
                            </span>
                        </h1>
                        <p className="text-xl text-neutral-300 mb-8 leading-relaxed">
                            Streamline your security operations with real-time attendance tracking,
                            face verification, and comprehensive workforce management—all in one powerful platform.
                        </p>
                        <div className="flex items-center justify-center gap-4">
                            <Link
                                href="/signup"
                                className="px-8 py-4 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors font-semibold text-lg shadow-lg shadow-blue-600/20"
                            >
                                Start Free Trial
                            </Link>
                            <Link
                                href="/select-role"
                                className="px-8 py-4 bg-neutral-800 text-white rounded-lg hover:bg-neutral-700 transition-colors font-semibold text-lg border border-neutral-700"
                            >
                                Sign In
                            </Link>
                        </div>
                    </div>

                    {/* Stats */}
                    <div className="mt-20 grid grid-cols-1 md:grid-cols-3 gap-8 max-w-4xl mx-auto">
                        <div className="text-center">
                            <div className="text-4xl font-bold text-blue-400 mb-2">10K+</div>
                            <div className="text-neutral-400">Security Guards</div>
                        </div>
                        <div className="text-center">
                            <div className="text-4xl font-bold text-blue-400 mb-2">500+</div>
                            <div className="text-neutral-400">Organizations</div>
                        </div>
                        <div className="text-center">
                            <div className="text-4xl font-bold text-blue-400 mb-2">99.9%</div>
                            <div className="text-neutral-400">Uptime</div>
                        </div>
                    </div>
                </div>
            </section>

            {/* Features Section */}
            <section id="features" className="py-20 px-6 bg-neutral-900/50">
                <div className="max-w-7xl mx-auto">
                    <div className="text-center mb-16">
                        <h2 className="text-4xl font-bold text-white mb-4">Powerful Features</h2>
                        <p className="text-xl text-neutral-400">Everything you need to manage your security workforce</p>
                    </div>

                    <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
                        {/* Feature 1 */}
                        <div className="bg-neutral-800/50 backdrop-blur-sm border border-neutral-700 rounded-2xl p-8 hover:border-blue-600 transition-all">
                            <div className="w-14 h-14 rounded-lg bg-blue-600/20 flex items-center justify-center mb-6">
                                <svg className="w-7 h-7 text-blue-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 9a2 2 0 012-2h.93a2 2 0 001.664-.89l.812-1.22A2 2 0 0110.07 4h3.86a2 2 0 011.664.89l.812 1.22A2 2 0 0018.07 7H19a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V9z" />
                                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 13a3 3 0 11-6 0 3 3 0 016 0z" />
                                </svg>
                            </div>
                            <h3 className="text-xl font-semibold text-white mb-3">Photo Attendance</h3>
                            <p className="text-neutral-400">
                                Real-time check-in/out with photo verification and GPS location tracking
                            </p>
                        </div>

                        {/* Feature 2 */}
                        <div className="bg-neutral-800/50 backdrop-blur-sm border border-neutral-700 rounded-2xl p-8 hover:border-blue-600 transition-all">
                            <div className="w-14 h-14 rounded-lg bg-green-600/20 flex items-center justify-center mb-6">
                                <svg className="w-7 h-7 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                                </svg>
                            </div>
                            <h3 className="text-xl font-semibold text-white mb-3">Face Verification</h3>
                            <p className="text-neutral-400">
                                AI-powered face matching to prevent buddy punching and fraud
                            </p>
                        </div>

                        {/* Feature 3 */}
                        <div className="bg-neutral-800/50 backdrop-blur-sm border border-neutral-700 rounded-2xl p-8 hover:border-blue-600 transition-all">
                            <div className="w-14 h-14 rounded-lg bg-purple-600/20 flex items-center justify-center mb-6">
                                <svg className="w-7 h-7 text-purple-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
                                </svg>
                            </div>
                            <h3 className="text-xl font-semibold text-white mb-3">Analytics & Reports</h3>
                            <p className="text-neutral-400">
                                Comprehensive insights into attendance, shifts, and workforce performance
                            </p>
                        </div>

                        {/* Feature 4 */}
                        <div className="bg-neutral-800/50 backdrop-blur-sm border border-neutral-700 rounded-2xl p-8 hover:border-blue-600 transition-all">
                            <div className="w-14 h-14 rounded-lg bg-yellow-600/20 flex items-center justify-center mb-6">
                                <svg className="w-7 h-7 text-yellow-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                                </svg>
                            </div>
                            <h3 className="text-xl font-semibold text-white mb-3">Shift Management</h3>
                            <p className="text-neutral-400">
                                Flexible day/night shift scheduling with automated assignments
                            </p>
                        </div>

                        {/* Feature 5 */}
                        <div className="bg-neutral-800/50 backdrop-blur-sm border border-neutral-700 rounded-2xl p-8 hover:border-blue-600 transition-all">
                            <div className="w-14 h-14 rounded-lg bg-red-600/20 flex items-center justify-center mb-6">
                                <svg className="w-7 h-7 text-red-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
                                </svg>
                            </div>
                            <h3 className="text-xl font-semibold text-white mb-3">Multi-Tenant SaaS</h3>
                            <p className="text-neutral-400">
                                Complete isolation for each organization with role-based access control
                            </p>
                        </div>

                        {/* Feature 6 */}
                        <div className="bg-neutral-800/50 backdrop-blur-sm border border-neutral-700 rounded-2xl p-8 hover:border-blue-600 transition-all">
                            <div className="w-14 h-14 rounded-lg bg-cyan-600/20 flex items-center justify-center mb-6">
                                <svg className="w-7 h-7 text-cyan-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 18h.01M8 21h8a2 2 0 002-2V5a2 2 0 00-2-2H8a2 2 0 00-2 2v14a2 2 0 002 2z" />
                                </svg>
                            </div>
                            <h3 className="text-xl font-semibold text-white mb-3">Mobile Ready</h3>
                            <p className="text-neutral-400">
                                Cross-platform mobile apps for guards and supervisors on the go
                            </p>
                        </div>
                    </div>
                </div>
            </section>

            {/* CTA Section */}
            <section className="py-20 px-6">
                <div className="max-w-4xl mx-auto text-center">
                    <h2 className="text-4xl font-bold text-white mb-6">Ready to get started?</h2>
                    <p className="text-xl text-neutral-300 mb-8">
                        Join hundreds of organizations managing their security workforce with Voylox
                    </p>
                    <Link
                        href="/signup"
                        className="inline-block px-8 py-4 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors font-semibold text-lg shadow-lg shadow-blue-600/20"
                    >
                        Start Your Free Trial
                    </Link>
                </div>
            </section>

            {/* Footer */}
            <footer className="border-t border-neutral-800 py-12 px-6">
                <div className="max-w-7xl mx-auto">
                    <div className="grid grid-cols-1 md:grid-cols-4 gap-8 mb-8">
                        <div>
                            <h3 className="text-white font-semibold mb-4">Voylox</h3>
                            <p className="text-neutral-400 text-sm">
                                Modern security workforce management platform
                            </p>
                        </div>
                        <div>
                            <h4 className="text-white font-semibold mb-4">Product</h4>
                            <ul className="space-y-2 text-neutral-400 text-sm">
                                <li><a href="#" className="hover:text-white">Features</a></li>
                                <li><a href="#" className="hover:text-white">Pricing</a></li>
                                <li><a href="#" className="hover:text-white">Security</a></li>
                            </ul>
                        </div>
                        <div>
                            <h4 className="text-white font-semibold mb-4">Company</h4>
                            <ul className="space-y-2 text-neutral-400 text-sm">
                                <li><a href="#" className="hover:text-white">About</a></li>
                                <li><a href="#" className="hover:text-white">Blog</a></li>
                                <li><a href="#" className="hover:text-white">Careers</a></li>
                            </ul>
                        </div>
                        <div>
                            <h4 className="text-white font-semibold mb-4">Support</h4>
                            <ul className="space-y-2 text-neutral-400 text-sm">
                                <li><a href="#" className="hover:text-white">Help Center</a></li>
                                <li><a href="#" className="hover:text-white">Contact</a></li>
                                <li><a href="#" className="hover:text-white">Status</a></li>
                            </ul>
                        </div>
                    </div>
                    <div className="border-t border-neutral-800 pt-8 text-center text-neutral-400 text-sm">
                        <p>© 2026 Voylox. All rights reserved.</p>
                    </div>
                </div>
            </footer>
        </div>
    )
}
