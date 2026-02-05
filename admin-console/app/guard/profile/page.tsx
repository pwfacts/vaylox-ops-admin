'use client'

import { useState, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { getGuardProfile, updateGuardProfile, updateGuardProfilePhoto, uploadGuardDocument } from '@/app/actions/guard-auth'
import ImageKitUpload from '@/components/ImageKitUpload'
import Image from 'next/image'

export default function GuardProfilePage() {
    const router = useRouter()
    const [guard, setGuard] = useState<any>(null)
    const [loading, setLoading] = useState(true)
    const [saving, setSaving] = useState(false)
    const [error, setError] = useState('')
    const [success, setSuccess] = useState('')
    const [editing, setEditing] = useState(false)

    const [formData, setFormData] = useState({
        date_of_birth: '',
        blood_group: '',
        emergency_contact_name: '',
        emergency_contact_phone: '',
        permanent_address: '',
        current_address: '',
        aadhar_number: '',
        pan_number: ''
    })

    useEffect(() => {
        loadProfile()
    }, [])

    async function loadProfile() {
        try {
            // In real app, get guard_id from session
            const guardProfile = await getGuardProfile('GUARD_ID_FROM_SESSION')
            setGuard(guardProfile)

            // Populate form
            setFormData({
                date_of_birth: guardProfile.date_of_birth || '',
                blood_group: guardProfile.blood_group || '',
                emergency_contact_name: guardProfile.emergency_contact_name || '',
                emergency_contact_phone: guardProfile.emergency_contact_phone || '',
                permanent_address: guardProfile.permanent_address || '',
                current_address: guardProfile.current_address || '',
                aadhar_number: guardProfile.aadhar_number || '',
                pan_number: guardProfile.pan_number || ''
            })
        } catch (err: any) {
            setError(err.message)
        } finally {
            setLoading(false)
        }
    }

    async function handleProfileUpdate(e: React.FormEvent) {
        e.preventDefault()
        setSaving(true)
        setError('')
        setSuccess('')

        try {
            const result = await updateGuardProfile({
                guard_id: guard.id,
                profile_data: formData
            })

            if (!result.success) {
                setError(result.error || 'Failed to update profile')
            } else {
                setSuccess('Profile updated successfully!')
                setEditing(false)
                await loadProfile()
            }
        } catch (err: any) {
            setError(err.message)
        } finally {
            setSaving(false)
        }
    }

    async function handlePhotoUpload(url: string, fileId: string) {
        try {
            const result = await updateGuardProfilePhoto({
                guard_id: guard.id,
                photo_url: url,
                imagekit_file_id: fileId
            })

            if (!result.success) {
                setError(result.error || 'Failed to update photo')
            } else {
                setSuccess('Profile photo updated!')
                await loadProfile()
            }
        } catch (err: any) {
            setError(err.message)
        }
    }

    if (loading) {
        return (
            <div className="min-h-screen bg-neutral-950 flex items-center justify-center">
                <div className="text-white">Loading profile...</div>
            </div>
        )
    }

    return (
        <div className="min-h-screen bg-gradient-to-br from-neutral-900 via-neutral-950 to-blue-950 p-6">
            <div className="max-w-4xl mx-auto">
                {/* Header */}
                <div className="flex items-center justify-between mb-8">
                    <h1 className="text-3xl font-bold text-white">My Profile</h1>
                    <button
                        onClick={() => router.push('/guard/dashboard')}
                        className="px-4 py-2 text-neutral-400 hover:text-white transition-colors"
                    >
                        ← Back to Dashboard
                    </button>
                </div>

                {/* Messages */}
                {error && (
                    <div className="bg-red-900/20 border border-red-800 rounded-lg p-4 mb-6">
                        <p className="text-red-400">{error}</p>
                    </div>
                )}
                {success && (
                    <div className="bg-green-900/20 border border-green-800 rounded-lg p-4 mb-6">
                        <p className="text-green-400">{success}</p>
                    </div>
                )}

                {/* Profile Photo Section */}
                <div className="bg-neutral-900/50 backdrop-blur-sm border border-neutral-800 rounded-2xl p-6 mb-6">
                    <h2 className="text-xl font-semibold text-white mb-4">Profile Photo</h2>

                    <div className="flex items-center gap-6">
                        {guard?.profile_photo_url ? (
                            <Image
                                src={guard.profile_photo_url}
                                alt="Profile"
                                width={128}
                                height={128}
                                className="w-32 h-32 rounded-full object-cover border-4 border-blue-600"
                            />
                        ) : (
                            <div className="w-32 h-32 rounded-full bg-neutral-800 border-4 border-neutral-700 flex items-center justify-center">
                                <svg className="w-16 h-16 text-neutral-600" fill="currentColor" viewBox="0 0 24 24">
                                    <path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z" />
                                </svg>
                            </div>
                        )}

                        <ImageKitUpload
                            onUploadComplete={handlePhotoUpload}
                            onUploadError={(err) => setError(err)}
                            folder="guards/profile"
                            buttonText="Upload New Photo"
                            acceptedTypes="image/*"
                        />
                    </div>
                </div>

                {/* Basic Info Section */}
                <div className="bg-neutral-900/50 backdrop-blur-sm border border-neutral-800 rounded-2xl p-6 mb-6">
                    <div className="flex items-center justify-between mb-4">
                        <h2 className="text-xl font-semibold text-white">Basic Information</h2>
                        {!editing && (
                            <button
                                onClick={() => setEditing(true)}
                                className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
                            >
                                Edit Profile
                            </button>
                        )}
                    </div>

                    <div className="grid grid-cols-2 gap-4 text-sm mb-4">
                        <div>
                            <span className="text-neutral-400">Name:</span>
                            <p className="text-white font-medium">{guard?.full_name}</p>
                        </div>
                        <div>
                            <span className="text-neutral-400">Guard Code:</span>
                            <p className="text-white font-medium">{guard?.guard_code}</p>
                        </div>
                        <div>
                            <span className="text-neutral-400">Email:</span>
                            <p className="text-white font-medium">{guard?.email}</p>
                        </div>
                        <div>
                            <span className="text-neutral-400">Phone:</span>
                            <p className="text-white font-medium">{guard?.phone_number}</p>
                        </div>
                    </div>

                    {editing ? (
                        <form onSubmit={handleProfileUpdate} className="space-y-4 mt-6">
                            <div className="grid grid-cols-2 gap-4">
                                <div>
                                    <label className="block text-sm font-medium text-neutral-300 mb-2">
                                        Date of Birth
                                    </label>
                                    <input
                                        type="date"
                                        value={formData.date_of_birth}
                                        onChange={(e) => setFormData({ ...formData, date_of_birth: e.target.value })}
                                        className="w-full px-4 py-2 bg-neutral-800 border border-neutral-700 rounded-lg text-white focus:outline-none focus:border-blue-500"
                                    />
                                </div>

                                <div>
                                    <label className="block text-sm font-medium text-neutral-300 mb-2">
                                        Blood Group
                                    </label>
                                    <select
                                        value={formData.blood_group}
                                        onChange={(e) => setFormData({ ...formData, blood_group: e.target.value })}
                                        className="w-full px-4 py-2 bg-neutral-800 border border-neutral-700 rounded-lg text-white focus:outline-none focus:border-blue-500"
                                    >
                                        <option value="">Select...</option>
                                        <option value="A+">A+</option>
                                        <option value="A-">A-</option>
                                        <option value="B+">B+</option>
                                        <option value="B-">B-</option>
                                        <option value="AB+">AB+</option>
                                        <option value="AB-">AB-</option>
                                        <option value="O+">O+</option>
                                        <option value="O-">O-</option>
                                    </select>
                                </div>

                                <div>
                                    <label className="block text-sm font-medium text-neutral-300 mb-2">
                                        Emergency Contact Name
                                    </label>
                                    <input
                                        type="text"
                                        value={formData.emergency_contact_name}
                                        onChange={(e) => setFormData({ ...formData, emergency_contact_name: e.target.value })}
                                        className="w-full px-4 py-2 bg-neutral-800 border border-neutral-700 rounded-lg text-white focus:outline-none focus:border-blue-500"
                                    />
                                </div>

                                <div>
                                    <label className="block text-sm font-medium text-neutral-300 mb-2">
                                        Emergency Contact Phone
                                    </label>
                                    <input
                                        type="tel"
                                        value={formData.emergency_contact_phone}
                                        onChange={(e) => setFormData({ ...formData, emergency_contact_phone: e.target.value })}
                                        className="w-full px-4 py-2 bg-neutral-800 border border-neutral-700 rounded-lg text-white focus:outline-none focus:border-blue-500"
                                    />
                                </div>

                                <div>
                                    <label className="block text-sm font-medium text-neutral-300 mb-2">
                                        Aadhar Number
                                    </label>
                                    <input
                                        type="text"
                                        value={formData.aadhar_number}
                                        onChange={(e) => setFormData({ ...formData, aadhar_number: e.target.value })}
                                        placeholder="XXXX-XXXX-XXXX"
                                        className="w-full px-4 py-2 bg-neutral-800 border border-neutral-700 rounded-lg text-white focus:outline-none focus:border-blue-500"
                                    />
                                </div>

                                <div>
                                    <label className="block text-sm font-medium text-neutral-300 mb-2">
                                        PAN Number
                                    </label>
                                    <input
                                        type="text"
                                        value={formData.pan_number}
                                        onChange={(e) => setFormData({ ...formData, pan_number: e.target.value })}
                                        placeholder="ABCDE1234F"
                                        className="w-full px-4 py-2 bg-neutral-800 border border-neutral-700 rounded-lg text-white focus:outline-none focus:border-blue-500"
                                    />
                                </div>
                            </div>

                            <div>
                                <label className="block text-sm font-medium text-neutral-300 mb-2">
                                    Permanent Address
                                </label>
                                <textarea
                                    value={formData.permanent_address}
                                    onChange={(e) => setFormData({ ...formData, permanent_address: e.target.value })}
                                    rows={2}
                                    className="w-full px-4 py-2 bg-neutral-800 border border-neutral-700 rounded-lg text-white focus:outline-none focus:border-blue-500"
                                />
                            </div>

                            <div>
                                <label className="block text-sm font-medium text-neutral-300 mb-2">
                                    Current Address
                                </label>
                                <textarea
                                    value={formData.current_address}
                                    onChange={(e) => setFormData({ ...formData, current_address: e.target.value })}
                                    rows={2}
                                    className="w-full px-4 py-2 bg-neutral-800 border border-neutral-700 rounded-lg text-white focus:outline-none focus:border-blue-500"
                                />
                            </div>

                            <div className="flex gap-3">
                                <button
                                    type="submit"
                                    disabled={saving}
                                    className="px-6 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors disabled:opacity-50"
                                >
                                    {saving ? 'Saving...' : 'Save Changes'}
                                </button>
                                <button
                                    type="button"
                                    onClick={() => setEditing(false)}
                                    className="px-6 py-2 bg-neutral-700 text-white rounded-lg hover:bg-neutral-600 transition-colors"
                                >
                                    Cancel
                                </button>
                            </div>
                        </form>
                    ) : (
                        <div className="grid grid-cols-2 gap-4 mt-6 text-sm">
                            <div>
                                <span className="text-neutral-400">Date of Birth:</span>
                                <p className="text-white">{formData.date_of_birth || 'Not set'}</p>
                            </div>
                            <div>
                                <span className="text-neutral-400">Blood Group:</span>
                                <p className="text-white">{formData.blood_group || 'Not set'}</p>
                            </div>
                            <div>
                                <span className="text-neutral-400">Emergency Contact:</span>
                                <p className="text-white">{formData.emergency_contact_name || 'Not set'}</p>
                            </div>
                            <div>
                                <span className="text-neutral-400">Emergency Phone:</span>
                                <p className="text-white">{formData.emergency_contact_phone || 'Not set'}</p>
                            </div>
                            <div className="col-span-2">
                                <span className="text-neutral-400">Permanent Address:</span>
                                <p className="text-white">{formData.permanent_address || 'Not set'}</p>
                            </div>
                            <div className="col-span-2">
                                <span className="text-neutral-400">Current Address:</span>
                                <p className="text-white">{formData.current_address || 'Not set'}</p>
                            </div>
                        </div>
                    )}
                </div>

                {/* Documents Section */}
                <div className="bg-neutral-900/50 backdrop-blur-sm border border-neutral-800 rounded-2xl p-6">
                    <h2 className="text-xl font-semibold text-white mb-4">My Documents</h2>

                    {guard?.documents && guard.documents.length > 0 ? (
                        <div className="grid gap-3">
                            {guard.documents.map((doc: any) => (
                                <div key={doc.id} className="flex items-center justify-between p-4 bg-neutral-800/50 rounded-lg">
                                    <div>
                                        <p className="text-white font-medium">{doc.document_type.replace('_', ' ').toUpperCase()}</p>
                                        <p className="text-neutral-400 text-sm">{doc.file_name}</p>
                                    </div>
                                    <a
                                        href={doc.document_url}
                                        target="_blank"
                                        rel="noopener noreferrer"
                                        className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors text-sm"
                                    >
                                        View
                                    </a>
                                </div>
                            ))}
                        </div>
                    ) : (
                        <p className="text-neutral-400">No documents uploaded yet</p>
                    )}
                </div>
            </div>
        </div>
    )
}
