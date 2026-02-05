import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'
import { createServerClient } from '@supabase/ssr'

export async function middleware(request: NextRequest) {
    let response = NextResponse.next({
        request: {
            headers: request.headers,
        },
    })

    const supabase = createServerClient(
        process.env.NEXT_PUBLIC_SUPABASE_URL!,
        process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
        {
            cookies: {
                get(name: string) {
                    return request.cookies.get(name)?.value
                },
                set(name: string, value: string, options) {
                    request.cookies.set({
                        name,
                        value,
                        ...options,
                    })
                    response = NextResponse.next({
                        request: {
                            headers: request.headers,
                        },
                    })
                    response.cookies.set({
                        name,
                        value,
                        ...options,
                    })
                },
                remove(name: string, options) {
                    request.cookies.set({
                        name,
                        value: '',
                        ...options,
                    })
                    response = NextResponse.next({
                        request: {
                            headers: request.headers,
                        },
                    })
                    response.cookies.set({
                        name,
                        value: '',
                        ...options,
                    })
                },
            },
        }
    )

    const { data: { user } } = await supabase.auth.getUser()

    // Public routes - allow without auth
    const publicRoutes = ['/', '/select-role', '/login', '/signup', '/auth/callback']
    const isPublicRoute = publicRoutes.some(route => request.nextUrl.pathname === route)

    if (isPublicRoute) {
        // Landing page and role selector - always allow
        if (request.nextUrl.pathname === '/' || request.nextUrl.pathname === '/select-role') {
            return response
        }

        // Login/signup - redirect if already authenticated
        if (user && (request.nextUrl.pathname === '/login' || request.nextUrl.pathname === '/signup')) {
            // Check if platform admin
            const { data: platformAdmin } = await supabase
                .from('platform_admins')
                .select('id')
                .eq('user_id', user.id)
                .maybeSingle()

            if (platformAdmin) {
                return NextResponse.redirect(new URL('/platform', request.url))
            }

            // Check if guard
            const { data: guard } = await supabase
                .from('guards')
                .select('id')
                .eq('user_id', user.id)
                .maybeSingle()

            if (guard) {
                return NextResponse.redirect(new URL('/guard/dashboard', request.url))
            }

            // Default to org dashboard
            return NextResponse.redirect(new URL('/dashboard', request.url))
        }

        return response
    }

    // Protected routes - require auth
    if (!user) {
        return NextResponse.redirect(new URL('/login', request.url))
    }

    // Platform admin routes - only for super admins
    if (request.nextUrl.pathname.startsWith('/platform')) {
        const { data: platformAdmin } = await supabase
            .from('platform_admins')
            .select('id')
            .eq('user_id', user.id)
            .maybeSingle()

        if (!platformAdmin) {
            // Not a platform admin - redirect to org dashboard
            return NextResponse.redirect(new URL('/', request.url))
        }

        return response
    }

    // Guard terminal - only for guards
    if (request.nextUrl.pathname === '/guard' ||
        request.nextUrl.pathname.startsWith('/guard/')) {

        // Future: Check if user is a guard
        // const { data: guard } = await supabase
        //   .from('guards')
        //   .select('id')
        //   .eq('user_id', user.id)
        //   .maybeSingle()

        // if (!guard) {
        //   return NextResponse.redirect(new URL('/', request.url))
        // }

        return response
    }

    // Organization dashboard routes (/, /workforce, /attendance, /units)
    // Check if user is platform admin trying to access org routes
    const { data: platformAdmin } = await supabase
        .from('platform_admins')
        .select('id')
        .eq('user_id', user.id)
        .maybeSingle()

    if (platformAdmin) {
        // Platform admin should not access org routes
        // Redirect them to platform
        return NextResponse.redirect(new URL('/platform', request.url))
    }

    // Check if user belongs to an organization
    const { data: orgUser } = await supabase
        .from('organization_users')
        .select('organization_id')
        .eq('user_id', user.id)
        .maybeSingle()

    if (!orgUser) {
        // User not associated with any organization
        // Redirect to a "no access" page or signup
        return NextResponse.redirect(new URL('/signup', request.url))
    }

    return response
}

export const config = {
    matcher: [
        /*
         * Match all request paths except:
         * - _next/static (static files)
         * - _next/image (image optimization files)
         * - favicon.ico (favicon file)
         * - public files (public folder)
         */
        '/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)',
    ],
}
