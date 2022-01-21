// Copyright 2021 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import BraveCore
import SwiftUI
import BraveUI

class BraveCertificate: ObservableObject {
    @Published var value: BraveCertificateModel
    
    init(model: BraveCertificateModel) {
        self.value = model
    }
    
    init?(name: String) {
        if let data = BraveCertificate.loadCertificateData(name: name),
           let certificate = SecCertificateCreateWithData(nil, data),
           let model = BraveCertificateModel(certificate: certificate) {
            self.value = model
            return
        }
        return nil
    }
    
    init?(certificate: SecCertificate) {
        if let model = BraveCertificateModel(certificate: certificate) {
            self.value = model
            return
        }
        return nil
    }
    
    private static func loadCertificateData(name: String) -> CFData? {
        guard let path = Bundle.main.path(forResource: name, ofType: "cer") else {
            return nil
        }
        
        guard let certificateData = try? Data(contentsOf: URL(fileURLWithPath: path)) as CFData else {
            return nil
        }
        return certificateData
    }
    
    private static func loadCertificate(name: String) -> SecCertificate? {
        guard let certificateData = loadCertificateData(name: name) else {
            return nil
        }
        return SecCertificateCreateWithData(nil, certificateData)
    }
}

private struct Utils {
    static func formatHex(_ hexString: String, separator: String = " ") -> String {
        let n = 2
        let characters = Array(hexString)
        
        var result: String = ""
        stride(from: 0, to: characters.count, by: n).forEach {
            result += String(characters[$0..<min($0 + n, characters.count)])
            if $0 + n < characters.count {
                result += separator
            }
        }
        return result
    }
    
    static func formatDate(_ date: Date) -> String {
        let dateFormatter = DateFormatter().then {
            $0.dateStyle = .full
            $0.timeStyle = .full
        }
        return dateFormatter.string(from: date)
    }
    
    enum OIDConversionError: Error {
      case tooLarge
      case invalidRootArc
      case invalidBEREncoding
    }

    static func absolute_oid_to_oid(oid: String) throws -> [UInt8] {
      var list = [UInt64]()
      for value in oid.split(separator: ".") {
        if let result = UInt64(value, radix: 10) {
          list.append(result)
        } else {
          // We don't support larger than 64-bits per arc as it would require big-int.
          throw OIDConversionError.tooLarge
        }
      }
      
      let encode_octet_as_septet = { (octet: UInt64) -> [UInt8] in
        var octet = octet
        var encoded = [UInt8]()
        var value = UInt64(0x00)
        
        while octet >= 0x80 {
          encoded.insert(UInt8((octet & UInt64(0x7F)) | value), at: 0)
          octet >>= 7
          value = 0x80
        }
        encoded.insert(UInt8(octet | value), at: 0)
        return encoded
      }
      
      // Invalid encoding for the root arcs 0 and 1.
      // Invalid encoding the root arc is limited to 0, 1, and 2.
      if (list[0] < 0 || list[0] > 2) || (list[0] <= 1 && list[1] > 39) {
        throw OIDConversionError.invalidRootArc
      }
      
      var result = encode_octet_as_septet(list[0] * 40 + list[1])
      for i in 2..<list.count {
        result.append(contentsOf: encode_octet_as_septet(list[i]))
      }
      
      result.insert(UInt8(result.count), at: 0)
      result.insert(0x06, at: 0)
      return result
    }

    static func oid_to_absolute_oid(oid: [UInt8]) throws -> String {
      // Invalid BER encoding
      if oid.count < 2 {
        throw OIDConversionError.invalidBEREncoding
      }
      
      // Drop first 2 octets as it isn't needed for the calculation
      var X = UInt32(oid[2]) / 40
      let Y = UInt32(oid[2]) % 40
      var sub = UInt64(0)
      
      var dot_notation = String()
      if X > 2 {
        X = 2
        
        dot_notation = "\(X)"
        if (UInt32(oid[2]) & 0x80) != 0x00 {
          sub = 80
        } else {
          dot_notation = ".\(Y + ((X - 2) * 40))"
        }
      } else {
        dot_notation = "\(X).\(Y)"
      }
      
      // Drop first 2 octets as it isn't needed for the calculation
      // Start at the next octet
      var value = UInt64(0)
      for i in (sub != 0 ? 2 : 3)..<oid.count {
        value = (value << 7) | (UInt64(oid[i]) & 0x7F)
        if (UInt64(oid[i]) & 0x80) != 0x80 {
          dot_notation += ".\(value - sub)"
          sub = 0
          value = 0
        }
      }
      return dot_notation
    }
    
    static func absolute_oid_to_oid(oid: String) -> Data {
        do {
            let absolute_oid: [UInt8] = try absolute_oid_to_oid(oid: oid)
            return Data(bytes: absolute_oid, count: absolute_oid.count)
        } catch {
            return Data()
        }
    }

    static func oid_to_absolute_oid(oid: Data) -> String {
        do {
            return try oid_to_absolute_oid(oid: oid.getBytes())
        } catch {
            return String()
        }
    }
}

struct CertificateTitleView: View {
    let isRootCertificate: Bool
    let commonName: String
    
    var body: some View {
        HStack(alignment: .center, spacing: 15.0) {
            Image(uiImage: isRootCertificate ? #imageLiteral(resourceName: "Root") : #imageLiteral(resourceName: "Other"))
            VStack(alignment: .leading, spacing: 10.0) {
                Text(commonName)
                    .font(.system(size: 16.0, weight: .bold))
            }
        }.background(Color(UIColor.secondaryBraveGroupedBackground))
    }
}

struct CertificateKeyValueView: View, Hashable {
    let title: String
    let value: String?
    
    init(title: String, value: String? = nil) {
        self.title = title
        self.value = value
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 12.0) {
            Text(title)
                .font(.system(size: 12.0))
            Spacer()
            if let value = value, !value.isEmpty {
                Text(value)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.system(size: 12.0, weight: .medium))
            }
        }
    }
}

struct CertificateSectionView<ContentView>: View where ContentView: View {
    let title: String
    let values: [ContentView]
    
    var body: some View {
        Section(header: Text(title)
                    .font(.system(size: 12.0))) {
            
            ForEach(values.indices, id: \.self) {
                values[$0].listRowBackground(Color(UIColor.secondaryBraveGroupedBackground))
            }
        }
    }
}

struct CertificateView: View {
    @EnvironmentObject var model: BraveCertificate
    
    var body: some View {
        VStack {
            CertificateTitleView(isRootCertificate:
                                    model.value.isRootCertificate,
                                 commonName: model.value.subjectName.commonName).padding()
            
            if #available(iOS 14, *) {
                List {
                    content
                }
                .listStyle(InsetGroupedListStyle())
                .frame(maxHeight: .infinity)
                .environmentObject(model)
            } else {
                List {
                    content
                }
                .listStyle(GroupedListStyle())
                .frame(maxHeight: .infinity)
                .environmentObject(model)
            }
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
                                    value: "\(model.value.version)"),
                                
          // Signature Algorithm
          CertificateKeyValueView(title: "Signature Algorithm",
              value: "\(model.value.signature.digest) with \(model.value.signature.algorithm) Encryption (\(model.value.signature.absoluteObjectIdentifier.isEmpty ? Utils.oid_to_absolute_oid(oid: model.value.signature.objectIdentifier) : model.value.signature.absoluteObjectIdentifier))"),
          
          // Signature Algorithm Parameters
          signatureParametersView()
        ])
        
        // Validity info
        CertificateSectionView(title: "Validity Dates",
                               values: [
          // Not Valid Before
          CertificateKeyValueView(title: "Not Valid Before",
                                    value: Utils.formatDate(model.value.notValidBefore)),
        
          // Not Valid After
          CertificateKeyValueView(title: "Not Valid After",
                                    value: Utils.formatDate(model.value.notValidAfter))
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
        let subjectName = model.value.subjectName
        
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
        let issuerName = model.value.issuerName
        
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
        let serialNumber = model.value.serialNumber
        if Int64(serialNumber) != nil || UInt64(serialNumber) != nil {
            return "\(serialNumber)"
        }
        return Utils.formatHex(model.value.serialNumber)
    }
    
    private func signatureParametersView() -> CertificateKeyValueView {
        let signature = model.value.signature
        let parameters = signature.parameters.isEmpty ? "None" : Utils.formatHex(signature.parameters)
        return CertificateKeyValueView(title: "Parameters",
                                         value: parameters)
    }
    
    private func publicKeyInfoViews() -> [CertificateKeyValueView] {
        let publicKeyInfo = model.value.publicKeyInfo
        
        var algorithm = publicKeyInfo.algorithm
        if !publicKeyInfo.curveName.isEmpty {
            algorithm += " - \(publicKeyInfo.curveName)"
        }
        
        if !algorithm.isEmpty {
            algorithm += " Encryption "
            if publicKeyInfo.absoluteObjectIdentifier.isEmpty {
                algorithm += " (\(Utils.oid_to_absolute_oid(oid: publicKeyInfo.objectIdentifier)))"
            } else {
                algorithm += " (\(publicKeyInfo.absoluteObjectIdentifier))"
            }
        }
        
        let parameters = publicKeyInfo.parameters.isEmpty ? "None" : "\(publicKeyInfo.parameters.count / 2) bytes : \(Utils.formatHex(publicKeyInfo.parameters))"
        
        // TODO: Number Formatter
        let publicKey = "\(publicKeyInfo.keyBytesSize) bytes : \(Utils.formatHex(publicKeyInfo.keyHexEncoded))"
        
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
        let signature = model.value.signature
        return "\(signature.bytesSize) bytes : \(Utils.formatHex(signature.signatureHexEncoded))"
    }
    
    private func fingerprintViews() -> [CertificateKeyValueView] {
        let sha256Fingerprint = model.value.sha256Fingerprint
        let sha1Fingerprint = model.value.sha1Fingerprint
        
        return [
            CertificateKeyValueView(title: "SHA-256", value: Utils.formatHex(sha256Fingerprint.fingerprintHexEncoded)),
            CertificateKeyValueView(title: "SHA-1", value: Utils.formatHex(sha1Fingerprint.fingerprintHexEncoded))
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
    
    init(certificate: BraveCertificate) {
        super.init(nibName: nil, bundle: nil)
        
        let rootView = CertificateView().environmentObject(certificate)
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
