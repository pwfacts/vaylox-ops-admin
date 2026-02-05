'use client'

import { useState } from 'react'
import ImageKitUpload from '@/components/ImageKitUpload'
import { createGuardWithFullBio } from '@/app/actions/guard-onboarding'
import { useRouter } from 'next/navigation'

interface GuardOnboardingFormProps {
    units: Array<{ id: string; unit_name: string }>
    created_by: string
}

export default function GuardOnboardingForm({ units, created_by }: GuardOnboardingFormProps) {
    const router = useRouter()
    const [step, setStep] = useState(1)
    const [loading, setLoading] = useState(false)
    const [error, setError] = useState('')
    const [success, setSuccess] = useState<string | null>(null)

    const [formData, setFormData] = useState({
        // Basic
        full_name: '',
        father_name: '',
        mother_name: '',
        guard_code: '',
        date_of_birth: '',
        blood_group: '',

        // Contact
        email: '',
        phone_number: '',
        emergency_contact_name: '',
        emergency_contact_phone: '',
        emergency_contact_relation: '',

        // Address
        present_address: '',
        permanent_address: '',

        // Identity - URLs
        aadhar_number: '',
        aadhar_front_url: '',
        aadhar_front_imagekit_id: '',
        aadhar_back_url: '',
        aadhar_back_imagekit_id: '',
        pan_number: '',
        pan_card_url: '',
        pan_card_imagekit_id: '',

        // Bank
        bank_account_number: '',
        bank_name: '',
        bank_ifsc_code: '',
        bank_passbook_url: '',
        bank_passbook_imagekit_id: '',

        // Employment
        uan_number: '',
        primary_unit_id: '',
        assigned_shift: 'day' as 'day' | 'night' | 'rotating',
        shift_start_time: '09:00',
        shift_end_time: '18:00',
        employment_type: 'full_time',
        monthly_salary: 0,

        // Supervisor
        is_supervisor: false,
        supervised_unit_id: ''
    })

    const [additionalDocs, setAdditionalDocs] = useState<Array<{
        document_url: string
        imagekit_file_id: string
        file_name: string
        document_type: string
    }>>([])

    async function handleSubmit(e: React.FormEvent) {
        e.preventDefault()
        setError('')
        setLoading(true)

        try {
            // Validation
            if (!formData.aadhar_front_url || !formData.aadhar_back_url) {
                throw new Error('Aadhar card photos (front & back) are required')
            }

            const result = await createGuardWithFullBio({
                ...formData,
                additional_documents: additionalDocs,
                created_by
            })

            if (!result.success) {
                setError(result.error || 'Failed to create guard')
            } else {
                setSuccess(`Guard ${formData.full_name} onboarded successfully!`)
                setTimeout(() => {
                    router.push('/workforce')
                    router.refresh()
                }, 2000)
            }
        } catch (err: any) {
            setError(err.message)
        } finally {
            setLoading(false)
        }
    }

    const totalSteps = 5

    return (
        <div className="max-w-4xl mx-auto">
            {/* Progress */}
            <div className="mb-8">
                <div className="flex items-center justify-between mb-2">
                    <span className="text-sm text-neutral-400">Step {step} of {totalSteps}</span>
                    <span className="text-sm text-neutral-400">{Math.round((step / totalSteps) * 100)}% Complete</span>
                </div>
                <div className="w-full h-2 bg-neutral-800 rounded-full overflow-hidden">
                    <div
                        className="h-full bg-blue-600 transition-all duration-300"
                        style={{ width: `${(step / totalSteps) * 100}%` }}
                    />
                </div>
            </div>

            {success && (
                <div className="bg-green-900/20 border border-green-800 rounded-lg p-4 mb-6">
                    <p className="text-green-400">{success}</p>
                </div>
            )}

            {error && (
                <div className="bg-red-900/20 border border-red-800 rounded-lg p-4 mb-6">
                    <p className="text-red-400">{error}</p>
                </div>
            )}

            <form onSubmit={handleSubmit} className="space-y-8">
                {/* Step 1: Basic Info */}
                {step === 1 && (
                    <div className="bg-neutral-900/ border border-neutral-800 rounded-2xl p-6">
                        <h2 className="text-2xl font-bold text-white mb-6">Basic Information</h2>

                        <div className="grid grid-cols-2 gap-4">
                            <div className="col-span-2">
                                <label className="block text-sm font-medium text-neutral-300 mb-2">
                                    Full Name <span className="text-red-500">*</span>
                                </label>
                                <input
                                    type="text"
                                    required
                                    value={formData.full_name}
                                    onChange={(e) => setFormData({ ...formData, full_name: e.target.value })}
                                    className="w-full px-4 py-3 bg-neutral-800 border border-neutral-700 rounded-lg text-white"
                                />
                            </div>

                            <div>
                                <label className="block text-sm font-medium text-neutral-300 mb-2">
                                    Father's Name <span className="text-red-500">*</span>
                                </label>
                                <input
                                    type="text"
                                    required
                                    value={formData.father_name}
                                    onChange={(e) => setFormData({ ...formData, father_name: e.target.value })}
                                    className="w-full px-4 py-3 bg-neutral-800 border border-neutral-700 rounded-lg text-white"
                                />
                            </div>

                            <div>
                                <label className="block text-sm font-medium text-neutral-300 mb-2">
                                    Mother's Name
                                </label>
                                <input
                                    type="text"
                                    value={formData.mother_name}
                                    onChange={(e) => setFormData({ ...formData, mother_name: e.target.value })}
                                    className="w-full px-4 py-3 bg-neutral-800 border border-neutral-700 rounded-lg text-white"
                                />
                            </div>

                            <div>
                                <label className="block text-sm font-medium text-neutral-300 mb-2">
                                    Guard Code <span className="text-red-500">*</span>
                                </label>
                                <input
                                    type="text"
                                    required
                                    value={formData.guard_code}
                                    onChange={(e) => setFormData({ ...formData, guard_code: e.target.value.toUpperCase() })}
                                    placeholder="G001"
                                    className="w-full px-4 py-3 bg-neutral-800 border border-neutral-700 rounded-lg text-white"
                                />
                            </div>

                            <div>
                                <label className="block text-sm font-medium text-neutral-300 mb-2">
                                    Date of Birth <span className="text-red-500">*</span>
                                </label>
                                <input
                                    type="date"
                                    required
                                    value={formData.date_of_birth}
                                    onChange={(e) => setFormData({ ...formData, date_of_birth: e.target.value })}
                                    className="w-full px-4 py-3 bg-neutral-800 border border-neutral-700 rounded-lg text-white"
                                />
                            </div>

                            <div>
                                <label className="block text-sm font-medium text-neutral-300 mb-2">
                                    Blood Group
                                </label>
                                <select
                                    value={formData.blood_group}
                                    onChange={(e) => setFormData({ ...formData, blood_group: e.target.value })}
                                    className="w-full px-4 py-3 bg-neutral-800 border border-neutral-700 rounded-lg text-white"
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
                                    Email
                                </label>
                                <input
                                    type="email"
                                    value={formData.email}
                                    onChange={(e) => setFormData({ ...formData, email: e.target.value })}
                                    className="w-full px-4 py-3 bg-neutral-800 border border-neutral-700 rounded-lg text-white"
                                />
                            </div>
                        </div>
                    </div>
                )}

                {/* Step 2: Contact & Address */}
                {step === 2 && (
                    <div className="bg-neutral-900/80 border border-neutral-800 rounded-2xl p-6">
                        <h2 className="text-2xl font-bold text-white mb-6">Contact & Address</h2>

                        <div className="grid grid-cols-2 gap-4">
                            <div>
                                <label className="block text-sm font-medium text-neutral-300 mb-2">
                                    Primary Mobile <span className="text-red-500">*</span>
                                </label>
                                <input
                                    type="tel"
                                    required
                                    value={formData.phone_number}
                                    onChange={(e) => setFormData({ ...formData, phone_number: e.target.value })}
                                    placeholder="+91 XXXXXXXXXX"
                                    className="w-full px-4 py-3 bg-neutral-800 border border-neutral-700 rounded-lg text-white"
                                />
                            </div>

                            <div>
                                <label className="block text-sm font-medium text-neutral-300 mb-2">
                                    Emergency Contact Name <span className="text-red-500">*</span>
                                </label>
                                <input
                                    type="text"
                                    required
                                    value={formData.emergency_contact_name}
                                    onChange={(e) => setFormData({ ...formData, emergency_contact_name: e.target.value })}
                                    className="w-full px-4 py-3 bg-neutral-800 border border-neutral-700 rounded-lg text-white"
                                />
                            </div>

                            <div>
                                <label className="block text-sm font-medium text-neutral-300 mb-2">
                                    Emergency Contact Phone <span className="text-red-500">*</span>
                                </label>
                                <input
                                    type="tel"
                                    required
                                    value={formData.emergency_contact_phone}
                                    onChange={(e) => setFormData({ ...formData, emergency_contact_phone: e.target.value })}
                                    className="w-full px-4 py-3 bg-neutral-800 border border-neutral-700 rounded-lg text-white"
                                />
                            </div>

                            <div>
                                <label className="block text-sm font-medium text-neutral-300 mb-2">
                                    Relation
                                </label>
                                <input
                                    type="text"
                                    value={formData.emergency_contact_relation}
                                    onChange={(e) => setFormData({ ...formData, emergency_contact_relation: e.target.value })}
                                    placeholder="Father, Mother, Spouse, etc."
                                    className="w-full px-4 py-3 bg-neutral-800 border border-neutral-700 rounded-lg text-white"
                                />
                            </div>

                            <div className="col-span-2">
                                <label className="block text-sm font-medium text-neutral-300 mb-2">
                                    Present Address
                                </label>
                                <textarea
                                    value={formData.present_address}
                                    onChange={(e) => setFormData({ ...formData, present_address: e.target.value })}
                                    rows={2}
                                    className="w-full px-4 py-3 bg-neutral-800 border border-neutral-700 rounded-lg text-white"
                                />
                            </div>

                            <div className="col-span-2">
                                <label className="block text-sm font-medium text-neutral-300 mb-2">
                                    Permanent Address <span className="text-red-500">*</span>
                                </label>
                                <textarea
                                    required
                                    value={formData.permanent_address}
                                    onChange={(e) => setFormData({ ...formData, permanent_address: e.target.value })}
                                    rows={2}
                                    className="w-full px-4 py-3 bg-neutral-800 border border-neutral-700 rounded-lg text-white"
                                />
                                <button
                                    type="button"
                                    onClick={() => setFormData({ ...formData, present_address: formData.permanent_address })}
                                    className="mt-2 text-sm text-blue-400 hover:text-blue-300"
                                >
                                    Same as permanent address
                                </button>
                            </div>
                        </div>
                    </div>
                )}

                {/* Step 3: Continue with Identity Documents, Bank Details, Employment, etc. */}
                {/* ... */}

                {/* Navigation */}
                <div className="flex items-center justify-between pt-6">
                    {step > 1 && (
                        <button
                            type="button"
                            onClick={() => setStep(step - 1)}
                            className="px-6 py-3 bg-neutral-700 text-white rounded-lg hover:bg-neutral-600 transition-colors"
                        >
                            ← Previous
                        </button>
                    )}

                    {step < totalSteps ? (
                        <button
                            type="button"
                            onClick={() => setStep(step + 1)}
                            className="ml-auto px-6 py-3 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
                        >
                            Next →
                        </button>
                    ) : (
                        <button
                            type="submit"
                            disabled={loading}
                            className="ml-auto px-6 py-3 bg-green-600 text-white rounded-lg hover:bg-green-700 transition-colors disabled:opacity-50"
                        >
                            {loading ? 'Creating...' : 'Complete Onboarding'}
                        </button>
                    )}
                </div>
            </form>
        </div>
    )
}
