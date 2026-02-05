'use client'

import { useState, useRef, useEffect } from 'react'
import { markAttendance } from '@/app/actions/guard-onboarding'

interface PhotoAttendanceProps {
    guard_id: string
    guard_name: string
    unit_id: string
    currentStatus: 'IN' | 'OUT' | 'ABSENT'
}

export default function PhotoAttendance({ guard_id, guard_name, unit_id, currentStatus }: PhotoAttendanceProps) {
    const [showCamera, setShowCamera] = useState(false)
    const [capturing, setCapturing] = useState(false)
    const [photo, setPhoto] = useState<string | null>(null)
    const [loading, setLoading] = useState(false)
    const [error, setError] = useState('')
    const [success, setSuccess] = useState('')
    const [location, setLocation] = useState<{
        latitude: number
        longitude: number
        accuracy: number
    } | null>(null)

    const videoRef = useRef<HTMLVideoElement>(null)
    const canvasRef = useRef<HTMLCanvasElement>(null)
    const streamRef = useRef<MediaStream | null>(null)

    const punchType = currentStatus === 'IN' ? 'OUT' : 'IN'

    useEffect(() => {
        // Get location when component mounts
        if ('geolocation' in navigator) {
            navigator.geolocation.getCurrentPosition(
                (position) => {
                    setLocation({
                        latitude: position.coords.latitude,
                        longitude: position.coords.longitude,
                        accuracy: position.coords.accuracy
                    })
                },
                (error) => {
                    console.error('Location error:', error)
                }
            )
        }
    }, [])

    async function startCamera() {
        setError('')
        try {
            const stream = await navigator.mediaDevices.getUserMedia({
                video: { facingMode: 'user', width: 1280, height: 720 },
                audio: false
            })

            if (videoRef.current) {
                videoRef.current.srcObject = stream
                streamRef.current = stream
                setShowCamera(true)
            }
        } catch (err: any) {
            setError('Unable to access camera. Please grant camera permission.')
        }
    }

    function stopCamera() {
        if (streamRef.current) {
            streamRef.current.getTracks().forEach(track => track.stop())
            streamRef.current = null
        }
        setShowCamera(false)
        setPhoto(null)
    }

    function capturePhoto() {
        if (!videoRef.current || !canvasRef.current) return

        const video = videoRef.current
        const canvas = canvasRef.current
        const context = canvas.getContext('2d')

        if (!context) return

        // Set canvas size to match video
        canvas.width = video.videoWidth
        canvas.height = video.videoHeight

        // Draw current video frame to canvas
        context.drawImage(video, 0, 0, canvas.width, canvas.height)

        // Get image data
        const imageData = canvas.toDataURL('image/jpeg', 0.8)
        setPhoto(imageData)
        setCapturing(true)

        // Stop camera
        stopCamera()
    }

    async function uploadPhotoAndMarkAttendance() {
        if (!photo) return

        setLoading(true)
        setError('')
        setSuccess('')

        try {
            // Convert base64 to blob
            const blob = await fetch(photo).then(r => r.blob())
            const file = new File([blob], `attendance_${Date.now()}.jpg`, { type: 'image/jpeg' })

            // Get ImageKit auth
            const authResponse = await fetch('/api/imagekit-auth')
            const authData = await authResponse.json()

            // Upload to ImageKit
            const formData = new FormData()
            formData.append('file', file)
            formData.append('fileName', file.name)
            formData.append('folder', 'attendance')
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
                throw new Error('Photo upload failed')
            }

            // Mark attendance
            const result = await markAttendance({
                guard_id,
                unit_id,
                punch_type: punchType,
                punch_photo_url: uploadData.url,
                punch_photo_imagekit_id: uploadData.fileId,
                latitude: location?.latitude,
                longitude: location?.longitude,
                location_accuracy: location?.accuracy
            })

            if (!result.success) {
                throw new Error(result.error || 'Failed to mark attendance')
            }

            setSuccess(`Punched ${punchType.toLowerCase()} successfully!`)
            setPhoto(null)
            setCapturing(false)

            // Refresh page after 2 seconds
            setTimeout(() => {
                window.location.reload()
            }, 2000)

        } catch (err: any) {
            setError(err.message || 'Failed to mark attendance')
            setCapturing(false)
        } finally {
            setLoading(false)
        }
    }

    return (
        <div className="space-y-4">
            {/* Status Badge */}
            <div className="flex items-center justify-between p-4 bg-neutral-800/50 rounded-lg">
                <div>
                    <p className="text-neutral-400 text-sm">Current Status</p>
                    <p className={`text-lg font-semibold ${currentStatus === 'IN' ? 'text-green-400' : 'text-neutral-400'
                        }`}>
                        {currentStatus === 'IN' ? 'Checked In' : 'Not Checked In'}
                    </p>
                </div>
                <div className={`px-4 py-2 rounded-lg ${currentStatus === 'IN'
                        ? 'bg-green-900/30 text-green-400'
                        : 'bg-neutral-700 text-neutral-400'
                    }`}>
                    {currentStatus}
                </div>
            </div>

            {/* Messages */}
            {error && (
                <div className="bg-red-900/20 border border-red-800 rounded-lg p-4">
                    <p className="text-red-400">{error}</p>
                </div>
            )}

            {success && (
                <div className="bg-green-900/20 border border-green-800 rounded-lg p-4">
                    <p className="text-green-400">{success}</p>
                </div>
            )}

            {!showCamera && !photo && (
                <button
                    onClick={startCamera}
                    disabled={loading}
                    className={`w-full px-6 py-4 rounded-lg font-semibold text-lg transition-colors ${punchType === 'IN'
                            ? 'bg-green-600 hover:bg-green-700 text-white'
                            : 'bg-red-600 hover:bg-red-700 text-white'
                        } disabled:opacity-50`}
                >
                    📸 Punch {punchType} - Take Photo
                </button>
            )}

            {/* Camera View */}
            {showCamera && (
                <div className="space-y-4">
                    <div className="relative bg-black rounded-lg overflow-hidden aspect-video">
                        <video
                            ref={videoRef}
                            autoPlay
                            playsInline
                            className="w-full h-full object-cover"
                        />
                        <div className="absolute inset-0 flex items-center justify-center">
                            <div className="w-64 h-80 border-4 border-white rounded-lg opacity-50"></div>
                        </div>
                        <p className="absolute top-4 left-1/2 -translate-x-1/2 bg-black/70 px-4 py-2 rounded text-white text-sm">
                            Align your face within the frame
                        </p>
                    </div>

                    <div className="grid grid-cols-2 gap-3">
                        <button
                            onClick={stopCamera}
                            className="px-4 py-3 bg-neutral-700 text-white rounded-lg hover:bg-neutral-600 transition-colors"
                        >
                            Cancel
                        </button>
                        <button
                            onClick={capturePhoto}
                            className="px-4 py-3 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
                        >
                            📸 Capture
                        </button>
                    </div>
                </div>
            )}

            {/* Photo Preview */}
            {photo && capturing && (
                <div className="space-y-4">
                    <div className="relative bg-black rounded-lg overflow-hidden">
                        <img src={photo} alt="Captured" className="w-full h-auto" />
                    </div>

                    <div className="bg-neutral-800/50 rounded-lg p-4">
                        <h3 className="text-white font-semibold mb-2">Confirm Attendance</h3>
                        <p className="text-neutral-400 text-sm mb-1">Guard: {guard_name}</p>
                        <p className="text-neutral-400 text-sm mb-1">Action: Punch {punchType}</p>
                        {location && (
                            <p className="text-neutral-400 text-sm">
                                Location: {location.latitude.toFixed(6)}, {location.longitude.toFixed(6)}
                            </p>
                        )}
                    </div>

                    <div className="grid grid-cols-2 gap-3">
                        <button
                            onClick={() => {
                                setPhoto(null)
                                setCapturing(false)
                            }}
                            disabled={loading}
                            className="px-4 py-3 bg-neutral-700 text-white rounded-lg hover:bg-neutral-600 transition-colors disabled:opacity-50"
                        >
                            Retake
                        </button>
                        <button
                            onClick={uploadPhotoAndMarkAttendance}
                            disabled={loading}
                            className="px-4 py-3 bg-green-600 text-white rounded-lg hover:bg-green-700 transition-colors disabled:opacity-50"
                        >
                            {loading ? 'Submitting...' : 'Confirm & Submit'}
                        </button>
                    </div>
                </div>
            )}

            {/* Hidden canvas for photo capture */}
            <canvas ref={canvasRef} className="hidden" />
        </div>
    )
}
