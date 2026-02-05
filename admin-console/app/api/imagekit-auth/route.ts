import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase'

export async function GET(req: NextRequest) {
    try {
        // Verify user is authenticated
        const supabase = await createClient()
        const { data: { user }, error: authError } = await supabase.auth.getUser()

        if (authError || !user) {
            return NextResponse.json(
                { error: 'Unauthorized' },
                { status: 401 }
            )
        }

        // Generate authentication parameters for ImageKit
        const token = crypto.randomUUID()
        const expire = Math.floor(Date.now() / 1000) + 3600 // 1 hour from now
        const publicKey = process.env.NEXT_PUBLIC_IMAGEKIT_PUBLIC_KEY!

        // Call edge function to generate signature
        const signatureResponse = await fetch(
            `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/imagekit-signature`,
            {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY}`
                },
                body: JSON.stringify({ token, expire })
            }
        )

        const { signature, error } = await signatureResponse.json()

        if (error) {
            throw new Error(error)
        }

        return NextResponse.json({
            token,
            expire,
            signature,
            publicKey
        })
    } catch (error: any) {
        console.error('ImageKit auth error:', error)
        return NextResponse.json(
            { error: error.message || 'Failed to generate auth' },
            { status: 500 }
        )
    }
}
