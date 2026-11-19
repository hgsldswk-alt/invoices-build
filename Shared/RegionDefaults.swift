import Foundation

struct RegionDefaults: Equatable {
    var currency: String
    var paper: String
    var tax: Tax
    var estimateWord: String
    var invoiceTitle: String
    var taxIDLabel: String
    init(region: String, localCurrency: String = "USD") {
        currency = localCurrency; paper = "a4"; tax = Tax(); estimateWord = "Estimate"; invoiceTitle = "Invoice"; taxIDLabel = "Tax ID"
        switch region {
        case "US": currency = "USD"; paper = "letter"; tax = Tax(name: "Sales Tax"); taxIDLabel = "EIN"
        case "CA": currency = "CAD"; paper = "letter"; tax = Tax(name: "GST", rate: 5); taxIDLabel = "GST/HST No."
        case "GB": currency = "GBP"; tax = Tax(name: "VAT", rate: 20); estimateWord = "Quote"; taxIDLabel = "VAT No."
        case "AU": currency = "AUD"; tax = Tax(name: "GST", rate: 10); estimateWord = "Quote"; invoiceTitle = "Tax Invoice"; taxIDLabel = "ABN"
        default: break
        }
    }
    static var current: RegionDefaults { RegionDefaults(region: Locale.current.region?.identifier ?? "US", localCurrency: Locale.current.currency?.identifier ?? "USD") }
}
