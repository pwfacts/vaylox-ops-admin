'use client'

import { useState, useRef } from 'react'

interface ImageKitUploadProps {
    onUploadComplete: (url: string, fileId: string) => void
    onUploadError: (error: string) => void
    folder?: string
    buttonText?: string
    acceptedTypes?: string
    className?: string
}

export default function ImageKitUpload({
    onUploadComplete,
    onUploadError,
    folder = 'guards',
    buttonText = 'Upload Photo',
    acceptedTypes = 'image/*',
    className = ''
}: ImageKitUploadProps) {
    const [uploading, setUploading] = useState(false)
    const [preview, setPreview] = useState<string | null>(null)
    const fileInputRef = useRef<HTMLInputElement>(null)

    async function handleFileChange(e: React.ChangeEvent<HTMLInputElement>) {
        const file = e.target.files?.[0]
        if (!file) return

        // Show preview
        const reader = new FileReader()
        reader.onloadend = () => {
            setPreview(reader.result as string)
        }
        reader.readAsDataURL(file)

        setUploading(true)

        try {
            // Step 1: Get ImageKit authentication parameters
            const authResponse = await fetch('/api/imagekit-auth')
            const authData = await authResponse.json()

            if (!authData.token || !authData.signature) {
                throw new Error('Failed to get ImageKit auth')
            }

            // Step 2: Upload to ImageKit
            const formData = new FormData()
            formData.append('file', file)
            formData.append('fileName', `${Date.now()}_${file.name}`)
            formData.append('folder', folder)
            formData.append('publicKey', authData.publicKey)
            formData.append('signature', authData.signature)
            formData.append('expire', authData.expire.toString())
            formData.append('token', authData.token)

            const uploadResponse = await fetch('https://upload.imagekit.io/api/v1/files/upload', {
                method: 'POST',
                body: formData
            })

            const uploadData = await uploadResponse.json()

            if (!uploadResponse.ok) {
                throw new Error(uploadData.message || 'Upload failed')
            }

            // Step 3: Call success callback
            onUploadComplete(uploadData.url, uploadData.fileId)

        } catch (error: any) {
            onUploadError(error.message || 'Upload failed')
            setPreview(null)
        } finally {
            setUploading(false)
        }
    }

    function triggerFileInput() {
        fileInputRef.current?.click()
    }

    return (
        <div className={className}>
            <input
                ref={fileInputRef}
                type="file"
                accept={acceptedTypes}
                onChange={handleFileChange}
                className="hidden"
            />

            {preview && (
                <div className="mb-4">
                    <img
                        src={preview}
                        alt="Preview"
                        className="w-32 h-32 object-cover rounded-lg border-2 border-blue-500"
                    />
                </div>
            )}

            <button
                type="button"
                onClick={triggerFileInput}
                disabled={uploading}
                className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            >
                {uploading ? 'Uploading...' : buttonText}
            </button>
        </div>
    )
}
