/** @type {import('next').NextConfig} */
const nextConfig = {
    images: {
        remotePatterns: [
            {
                protocol: 'https',
                hostname: 'ik.imagekit.io',
                pathname: '/**',
            },
            {
                protocol: 'https',
                hostname: '**.supabase.co',
                pathname: '/storage/**',
            },
        ],
    },
    // Ensure static files are properly handled
    output: 'standalone',
}

module.exports = nextConfig
