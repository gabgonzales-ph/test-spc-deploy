import { Shield, Eye, Lock, FileText, AlertCircle, Phone } from "lucide-react";

export default function PrivacyPolicy() {
  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header Section */}
      <section className="bg-gradient-to-br from-emerald-600 to-emerald-700 py-16 pt-40">
        <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center">
            <Shield className="mx-auto h-16 w-16 text-white mb-6" />
            <h1 className="text-4xl font-bold text-white mb-4">Privacy Policy</h1>
            <p className="text-xl text-emerald-100 max-w-2xl mx-auto">
              City Government of San Pablo, Laguna - Protecting Your Personal Information
            </p>
          </div>
        </div>
      </section>

      {/* Two Column Layout: Badge (left, sticky) + Content (right) */}
      <section className="py-10 bg-gray-50">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="grid grid-cols-1 lg:grid-cols-[minmax(0,280px)_1fr] gap-3 items-start">

            {/* Left Column: Sticky NPC Badge */}
            <div className="lg:sticky lg:top-30">
              <a
                href="https://npcregistration.privacy.gov.ph/certificate/organizationRegistration/67e0c664de42154e800b135b"
                target="_blank"
                rel="noopener noreferrer"
                className="group block bg-white rounded-2xl shadow-md border border-gray-200 p-8 text-center transition-all duration-300 ease-out hover:shadow-xl hover:-translate-y-1 hover:border-emerald-300 active:scale-95 active:shadow-md"
              >
                <img
                  src="/npc.jpg"
                  alt="National Privacy Commission DPO/DPS Registered Badge"
                  className="mx-auto h-70 w-auto transition-transform duration-300 ease-out group-hover:scale-105"
                />
                <p className="mt-5 text-sm font-medium text-gray-700 transition-colors duration-300 group-hover:text-emerald-700">
                  Registered with the National Privacy Commission
                </p>
                <p className="mt-1 text-xs text-gray-400 transition-colors duration-300 group-hover:text-emerald-500">
                  Click to view certificate
                </p>
              </a>
            </div>

            {/* Right Column: Content Section */}
            <div className="bg-white rounded-lg shadow-lg p-8">
            
            {/* Last Updated */}
            <div className="bg-emerald-50 border-l-4 border-emerald-400 p-4 mb-8">
              <div className="flex items-center">
                <AlertCircle className="h-5 w-5 text-emerald-600 mr-2" />
                <p className="text-sm text-emerald-800">
                  <strong>Last Updated:</strong> September 17, 2025
                </p>
              </div>
            </div>

            {/* Introduction */}
            <div className="mb-8">
              <h2 className="text-2xl font-bold text-gray-900 mb-4 flex items-center">
                <Eye className="h-6 w-6 text-emerald-600 mr-2" />
                Introduction
              </h2>
              <p className="text-gray-700 mb-4">
                The City Government of San Pablo, Laguna (&quot;San Pablo City&quot;, &quot;we&quot;, &quot;us&quot;, or &quot;our&quot;) is committed to protecting your privacy and personal information. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you visit our official website (sanpablocity.gov.ph) and use our digital services.
              </p>
              <p className="text-gray-700">
                As a Local Government Unit (LGU) of the Republic of the Philippines, we adhere to the Data Privacy Act of 2012 (RA 10173), its Implementing Rules and Regulations (IRR), and guidelines issued by the National Privacy Commission (NPC) and the Department of Information and Communications Technology (DICT).
              </p>
            </div>

            {/* Information We Collect */}
            <div className="mb-8">
              <h2 className="text-2xl font-bold text-gray-900 mb-4 flex items-center">
                <FileText className="h-6 w-6 text-emerald-600 mr-2" />
                Information We Collect
              </h2>
              
              <h3 className="text-xl font-semibold text-gray-800 mb-3">Personal Information</h3>
              <p className="text-gray-700 mb-4">
                We may collect the following personal information when you:
              </p>
              <ul className="list-disc pl-6 mb-4 space-y-2 text-gray-700">
                <li>Register for online services</li>
                <li>Apply for permits, licenses, or certificates</li>
                <li>Submit forms or applications</li>
                <li>Contact us through our website or email</li>
                <li>Participate in surveys or feedback forms</li>
              </ul>

              <div className="bg-gray-50 p-4 rounded-lg mb-4">
                <h4 className="font-semibold text-gray-800 mb-2">Types of Personal Data:</h4>
                <ul className="list-disc pl-6 space-y-1 text-gray-700">
                  <li>Full name and contact information (address, phone, email)</li>
                  <li>Government-issued ID numbers (TIN, SSS, PhilHealth, etc.)</li>
                  <li>Birth date and place of birth</li>
                  <li>Civil status and family information</li>
                  <li>Educational and employment background</li>
                  <li>Business information (for business registration)</li>
                  <li>Financial information (for tax-related services)</li>
                </ul>
              </div>

              <h3 className="text-xl font-semibold text-gray-800 mb-3">Technical Information</h3>
              <ul className="list-disc pl-6 space-y-2 text-gray-700">
                <li>IP address and browser information</li>
                <li>Device type and operating system</li>
                <li>Pages visited and time spent on our website</li>
                <li>Referring website or search terms used</li>
                <li>Cookies and similar tracking technologies</li>
              </ul>
            </div>

            {/* How We Use Your Information */}
            <div className="mb-8">
              <h2 className="text-2xl font-bold text-gray-900 mb-4">How We Use Your Information</h2>
              <p className="text-gray-700 mb-4">
                We process your personal information for the following purposes:
              </p>
              
              <div className="grid md:grid-cols-2 gap-4 mb-4">
                <div className="bg-emerald-50 p-4 rounded-lg">
                  <h4 className="font-semibold text-emerald-800 mb-2">Government Services</h4>
                  <ul className="text-sm text-emerald-700 space-y-1">
                    <li>• Processing applications and permits</li>
                    <li>• Issuing certificates and licenses</li>
                    <li>• Tax assessment and collection</li>
                    <li>• Public health and safety programs</li>
                  </ul>
                </div>
                <div className="bg-blue-50 p-4 rounded-lg">
                  <h4 className="font-semibold text-blue-800 mb-2">Communication</h4>
                  <ul className="text-sm text-blue-700 space-y-1">
                    <li>• Responding to inquiries</li>
                    <li>• Sending notifications and updates</li>
                    <li>• Emergency alerts and announcements</li>
                    <li>• Survey and feedback collection</li>
                  </ul>
                </div>
              </div>

              <div className="bg-yellow-50 border-l-4 border-yellow-400 p-4">
                <h4 className="font-semibold text-yellow-800 mb-2">Legal Basis for Processing</h4>
                <p className="text-sm text-yellow-700">
                  We process your personal data based on: (1) Performance of official functions and duties as mandated by law, (2) Legitimate interests of the LGU in providing public services, (3) Compliance with legal obligations, and (4) Your consent where required.
                </p>
              </div>
            </div>

            {/* Information Sharing */}
            <div className="mb-8">
              <h2 className="text-2xl font-bold text-gray-900 mb-4">Information Sharing and Disclosure</h2>
              <p className="text-gray-700 mb-4">
                We may share your personal information with:
              </p>
              <ul className="list-disc pl-6 space-y-2 text-gray-700 mb-4">
                <li><strong>Government Agencies:</strong> When required for inter-agency coordination and compliance with national programs</li>
                <li><strong>Third-Party Service Providers:</strong> Contracted entities that help us deliver services (subject to data processing agreements)</li>
                <li><strong>Law Enforcement:</strong> When required by law, court order, or legal process</li>
                <li><strong>Emergency Situations:</strong> To protect public health, safety, or welfare</li>
              </ul>
              <div className="bg-red-50 border border-red-200 p-4 rounded-lg">
                <p className="text-red-800 text-sm">
                  <strong>Important:</strong> We do not sell, trade, or rent your personal information to commercial entities for marketing purposes.
                </p>
              </div>
            </div>

            {/* Data Security */}
            <div className="mb-8">
              <h2 className="text-2xl font-bold text-gray-900 mb-4 flex items-center">
                <Lock className="h-6 w-6 text-emerald-600 mr-2" />
                Data Security
              </h2>
              <p className="text-gray-700 mb-4">
                We implement appropriate technical, organizational, and physical security measures to protect your personal information:
              </p>
              <div className="grid md:grid-cols-3 gap-4">
                <div className="bg-gray-50 p-4 rounded-lg">
                  <h4 className="font-semibold text-gray-800 mb-2">Technical Measures</h4>
                  <ul className="text-sm text-gray-700 space-y-1">
                    <li>• SSL encryption</li>
                    <li>• Secure servers</li>
                    <li>• Regular updates</li>
                    <li>• Access controls</li>
                  </ul>
                </div>
                <div className="bg-gray-50 p-4 rounded-lg">
                  <h4 className="font-semibold text-gray-800 mb-2">Administrative</h4>
                  <ul className="text-sm text-gray-700 space-y-1">
                    <li>• Staff training</li>
                    <li>• Privacy policies</li>
                    <li>• Audit procedures</li>
                    <li>• Incident response</li>
                  </ul>
                </div>
                <div className="bg-gray-50 p-4 rounded-lg">
                  <h4 className="font-semibold text-gray-800 mb-2">Physical Security</h4>
                  <ul className="text-sm text-gray-700 space-y-1">
                    <li>• Secure facilities</li>
                    <li>• Restricted access</li>
                    <li>• Document security</li>
                    <li>• Proper disposal</li>
                  </ul>
                </div>
              </div>
            </div>

            {/* Your Rights */}
            <div className="mb-8">
              <h2 className="text-2xl font-bold text-gray-900 mb-4">Your Data Privacy Rights</h2>
              <p className="text-gray-700 mb-4">
                Under the Data Privacy Act of 2012, you have the following rights:
              </p>
              <div className="space-y-3">
                <div className="border-l-4 border-emerald-400 bg-emerald-50 p-3">
                  <h4 className="font-semibold text-emerald-800">Right to be Informed</h4>
                  <p className="text-sm text-emerald-700">Know what personal data is being collected and how it&quot;s processed</p>
                </div>
                <div className="border-l-4 border-blue-400 bg-blue-50 p-3">
                  <h4 className="font-semibold text-blue-800">Right to Access</h4>
                  <p className="text-sm text-blue-700">Request access to your personal data we hold</p>
                </div>
                <div className="border-l-4 border-yellow-400 bg-yellow-50 p-3">
                  <h4 className="font-semibold text-yellow-800">Right to Rectification</h4>
                  <p className="text-sm text-yellow-700">Request correction of inaccurate or incomplete data</p>
                </div>
                <div className="border-l-4 border-red-400 bg-red-50 p-3">
                  <h4 className="font-semibold text-red-800">Right to Erasure/Blocking</h4>
                  <p className="text-sm text-red-700">Request deletion or blocking of data when legally permissible</p>
                </div>
              </div>
            </div>

            {/* Cookies */}
            <div className="mb-8">
              <h2 className="text-2xl font-bold text-gray-900 mb-4">Cookies and Tracking</h2>
              <p className="text-gray-700 mb-4">
                Our website uses cookies and similar technologies to improve your browsing experience and analyze website traffic. For detailed information, please see our Cookie Policy.
              </p>
            </div>

            {/* Contact Information */}
            <div className="mb-8">
              <h2 className="text-2xl font-bold text-gray-900 mb-4 flex items-center">
                <Phone className="h-6 w-6 text-emerald-600 mr-2" />
                Contact Information
              </h2>
              <div className="bg-emerald-50 p-6 rounded-lg">
                <h3 className="text-lg font-semibold text-emerald-800 mb-3">Data Protection Officer</h3>
                <div className="space-y-2 text-emerald-700">
                  <p><strong>Office:</strong> City Government of San Pablo, Laguna</p>
                  <p><strong>Address:</strong> City Hall, San Pablo City, Laguna</p>
                  <p><strong>Email:</strong> dpo@sanpablocity.gov.ph</p>
                  <p><strong>Phone:</strong> (049) 562-3156</p>
                </div>
                
                <div className="mt-4 pt-4 border-t border-emerald-200">
                  <p className="text-sm text-emerald-700">
                    For complaints or data privacy concerns, you may also contact the National Privacy Commission at:
                  </p>
                  <p className="text-sm text-emerald-700 mt-1">
                    <strong>Website:</strong> privacy.gov.ph | <strong>Email:</strong> info@privacy.gov.ph
                  </p>
                </div>
              </div>
            </div>

            {/* Changes to Policy */}
            <div className="mb-8">
              <h2 className="text-2xl font-bold text-gray-900 mb-4">Changes to This Policy</h2>
              <p className="text-gray-700">
                We may update this Privacy Policy from time to time to reflect changes in our practices or legal requirements. We will notify you of any significant changes by posting the updated policy on our website with a new &quot;Last Updated&quot; date. We encourage you to review this policy periodically.
              </p>
            </div>

            {/* Footer */}
            <div className="border-t border-gray-200 pt-6">
              <p className="text-sm text-gray-600 text-center">
                This Privacy Policy is issued in compliance with the Data Privacy Act of 2012 (RA 10173) and DICT Government Website Template Design Guidelines.
              </p>
            </div>

            </div>
          </div>
        </div>
      </section>
    </div>
  );
}