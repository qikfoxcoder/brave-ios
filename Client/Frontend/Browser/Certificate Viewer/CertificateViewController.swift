// Copyright 2021 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import BraveCore
import SwiftUI
import BraveUI

private struct CertificateTitleView: View {
    let isRootCertificate: Bool
    let commonName: String
    
    var body: some View {
        HStack(spacing: 15.0) {
            Image(uiImage: isRootCertificate ? #imageLiteral(resourceName: "Root") : #imageLiteral(resourceName: "Other"))
            VStack(alignment: .leading, spacing: 10.0) {
                Text(commonName)
                    .font(.callout.weight(.bold))
            }
        }
        .background(Color(.secondaryBraveGroupedBackground))
    }
}

private struct CertificateKeyValueView: View, Hashable {
    let title: String
    let value: String?
    
    var body: some View {
        HStack(spacing: 12.0) {
            Text(title)
                .font(.caption)
            Spacer()
            if let value = value, !value.isEmpty {
                Text(value)
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.caption.weight(.medium))
            }
        }
    }
}

private struct CertificateSectionView<ContentView>: View where ContentView: View {
    let title: String
    let values: [ContentView]
    
    var body: some View {
        Section(header: Text(title)
                    .font(.caption)) {
            
            ForEach(values.indices, id: \.self) {
                values[$0].listRowBackground(Color(.secondaryBraveGroupedBackground))
            }
        }
    }
}

private struct CertificateView: View {
    let model: BraveCertificateModel
    
    var body: some View {
        VStack {
            CertificateTitleView(isRootCertificate: model.isRootCertificate,
                                 commonName: model.subjectName.commonName)
                .padding()
            
            List {
                content
            }
            .listStyle(InsetGroupedListStyle())
        }
    }
    
    @ViewBuilder
    private var content: some View {
        // Subject name
        CertificateSectionView(title: "Subject Name", values: subjectNameViews())
        
        // Issuer name
        CertificateSectionView(title: "Issuer Name",
                               values: issuerNameViews())
        
        // Common info
        CertificateSectionView(title: "Common Info",
                               values: [
          // Serial number
          CertificateKeyValueView(title: "Serial Number",
                                    value: formattedSerialNumber()),
                                
          // Version
          CertificateKeyValueView(title: "Version",
                                    value: "\(model.version)"),
                                
          // Signature Algorithm
          CertificateKeyValueView(title: "Signature Algorithm",
              value: "\(model.signature.digest) with \(model.signature.algorithm) Encryption (\(model.signature.absoluteObjectIdentifier.isEmpty ? BraveCertificateUtils.oid_to_absolute_oid(oid: model.signature.objectIdentifier) : model.signature.absoluteObjectIdentifier))"),
          
          // Signature Algorithm Parameters
          signatureParametersView()
        ])
        
        // Validity info
        CertificateSectionView(title: "Validity Dates",
                               values: [
          // Not Valid Before
          CertificateKeyValueView(title: "Not Valid Before",
                                    value: BraveCertificateUtils.formatDate(model.notValidBefore)),
        
          // Not Valid After
          CertificateKeyValueView(title: "Not Valid After",
                                    value: BraveCertificateUtils.formatDate(model.notValidAfter))
        ])
        
        // Public Key Info
        CertificateSectionView(title: "Public Key info",
                               values: publicKeyInfoViews())
        
        // Signature
        CertificateSectionView(title: "Signature",
                               values: [
          CertificateKeyValueView(title: "Signature",
                                    value: formattedSignature())
        ])
        
        // Fingerprints
        CertificateSectionView(title: "Fingerprints",
                               values: fingerprintViews())
    }
}

extension CertificateView {
    private func subjectNameViews() -> [CertificateKeyValueView] {
        let subjectName = model.subjectName
        
        // Ordered mapping
        var mapping = [
            KeyValue(key: "Country or Region", value: subjectName.countryOrRegion),
            KeyValue(key: "State/Province", value: subjectName.stateOrProvince),
            KeyValue(key: "Locality", value: subjectName.locality)
        ]
        
        mapping.append(contentsOf: subjectName.organization.map {
            KeyValue(key: "Organization", value: "\($0)")
        })
        
        mapping.append(contentsOf: subjectName.organizationalUnit.map {
            KeyValue(key: "Organizational Unit", value: "\($0)")
        })
        
        mapping.append(KeyValue(key: "Common Name", value: subjectName.commonName))
        
        mapping.append(contentsOf: subjectName.streetAddress.map {
            KeyValue(key: "Street Address", value: "\($0)")
        })
        
        mapping.append(contentsOf: subjectName.domainComponent.map {
            KeyValue(key: "Domain Component", value: "\($0)")
        })

        mapping.append(KeyValue(key: "User ID", value: subjectName.userId))
        
        return mapping.compactMap({
            $0.value.isEmpty ? nil : CertificateKeyValueView(title: $0.key,
                                                               value: $0.value)
        })
    }
    
    private func issuerNameViews() -> [CertificateKeyValueView] {
        let issuerName = model.issuerName
        
        // Ordered mapping
        var mapping = [
            KeyValue(key: "Country or Region", value: issuerName.countryOrRegion),
            KeyValue(key: "State/Province", value: issuerName.stateOrProvince),
            KeyValue(key: "Locality", value: issuerName.locality)
        ]
        
        mapping.append(contentsOf: issuerName.organization.map {
            KeyValue(key: "Organization", value: "\($0)")
        })
        
        mapping.append(contentsOf: issuerName.organizationalUnit.map {
            KeyValue(key: "Organizational Unit", value: "\($0)")
        })
        
        mapping.append(KeyValue(key: "Common Name", value: issuerName.commonName))
        
        mapping.append(contentsOf: issuerName.streetAddress.map {
            KeyValue(key: "Street Address", value: "\($0)")
        })
        
        mapping.append(contentsOf: issuerName.domainComponent.map {
            KeyValue(key: "Domain Component", value: "\($0)")
        })

        mapping.append(KeyValue(key: "User ID", value: issuerName.userId))
        
        return mapping.compactMap({
            $0.value.isEmpty ? nil : CertificateKeyValueView(title: $0.key,
                                                               value: $0.value)
        })
    }
    
    private func formattedSerialNumber() -> String {
        let serialNumber = model.serialNumber
        if Int64(serialNumber) != nil || UInt64(serialNumber) != nil {
            return "\(serialNumber)"
        }
        return BraveCertificateUtils.formatHex(model.serialNumber)
    }
    
    private func signatureParametersView() -> CertificateKeyValueView {
        let signature = model.signature
        let parameters = signature.parameters.isEmpty ? "None" : BraveCertificateUtils.formatHex(signature.parameters)
        return CertificateKeyValueView(title: "Parameters",
                                         value: parameters)
    }
    
    private func publicKeyInfoViews() -> [CertificateKeyValueView] {
        let publicKeyInfo = model.publicKeyInfo
        
        var algorithm = publicKeyInfo.algorithm
        if !publicKeyInfo.curveName.isEmpty {
            algorithm += " - \(publicKeyInfo.curveName)"
        }
        
        if !algorithm.isEmpty {
            algorithm += " Encryption "
            if publicKeyInfo.absoluteObjectIdentifier.isEmpty {
                algorithm += " (\(BraveCertificateUtils.oid_to_absolute_oid(oid: publicKeyInfo.objectIdentifier)))"
            } else {
                algorithm += " (\(publicKeyInfo.absoluteObjectIdentifier))"
            }
        }
        
        let parameters = publicKeyInfo.parameters.isEmpty ? "None" : "\(publicKeyInfo.parameters.count / 2) bytes : \(BraveCertificateUtils.formatHex(publicKeyInfo.parameters))"
        
        // TODO: Number Formatter
        let publicKey = "\(publicKeyInfo.keyBytesSize) bytes : \(BraveCertificateUtils.formatHex(publicKeyInfo.keyHexEncoded))"
        
        // TODO: Number Formatter
        let keySizeInBits = "\(publicKeyInfo.keySizeInBits) bits"
        
        var keyUsages = [String]()
        if publicKeyInfo.keyUsage.contains(.ENCRYPT) {
            keyUsages.append("Encrypt")
        }
        
        if publicKeyInfo.keyUsage.contains(.VERIFY) {
            keyUsages.append("Verify")
        }
        
        if publicKeyInfo.keyUsage.contains(.WRAP) {
            keyUsages.append("Wrap")
        }
        
        if publicKeyInfo.keyUsage.contains(.DERIVE) {
            keyUsages.append("Derive")
        }
        
        if publicKeyInfo.keyUsage.isEmpty || publicKeyInfo.keyUsage == .INVALID || publicKeyInfo.keyUsage.contains(.ANY) {
            keyUsages.append("Any")
        }
        
        let exponent = publicKeyInfo.type == .RSA && publicKeyInfo.exponent != 0 ? "\(publicKeyInfo.exponent)" : ""
        
        // Ordered mapping
        let mapping = [
            KeyValue(key: "Algorithm", value: algorithm),
            KeyValue(key: "Parameters", value: parameters),
            KeyValue(key: "Public Key", value: publicKey),
            KeyValue(key: "Exponent", value: exponent),
            KeyValue(key: "Key Size", value: keySizeInBits),
            KeyValue(key: "Key Usage", value: keyUsages.joined(separator: " "))
        ]
        
        return mapping.compactMap({
            $0.value.isEmpty ? nil : CertificateKeyValueView(title: $0.key,
                                                             value: $0.value)
        })
    }
    
    private func formattedSignature() -> String {
        let signature = model.signature
        return "\(signature.bytesSize) bytes : \(BraveCertificateUtils.formatHex(signature.signatureHexEncoded))"
    }
    
    private func fingerprintViews() -> [CertificateKeyValueView] {
        let sha256Fingerprint = model.sha256Fingerprint
        let sha1Fingerprint = model.sha1Fingerprint
        
        return [
            CertificateKeyValueView(title: "SHA-256", value: BraveCertificateUtils.formatHex(sha256Fingerprint.fingerprintHexEncoded)),
            CertificateKeyValueView(title: "SHA-1", value: BraveCertificateUtils.formatHex(sha1Fingerprint.fingerprintHexEncoded))
        ]
    }
    
    private struct KeyValue {
        let key: String
        let value: String
    }
}

#if DEBUG
struct CertificateView_Previews: PreviewProvider {
    static var previews: some View {
        let model = BraveCertificate(name: "leaf")!

        CertificateView()
            .environmentObject(model)
    }
}
#endif

class CertificateViewController: UIViewController, PopoverContentComponent {
    
    init(certificate: BraveCertificateModel) {
        super.init(nibName: nil, bundle: nil)
        
        let rootView = CertificateView(model: certificate)
        let controller = UIHostingController(rootView: rootView)
        
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controller.view)
        controller.didMove(toParent: self)
        
        controller.view.snp.makeConstraints {
            $0.edges.equalToSuperview()
        }
        
        self.preferredContentSize = CGSize(width: UIScreen.main.bounds.width, height: 1000)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
