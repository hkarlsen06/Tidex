import XCTest

@testable import Tidex

final class OnboardingCurrencyResolverTests: XCTestCase {
  private let carryoverKey = "preAuthPreferredCurrency"

  override func tearDown() {
    UserDefaults.standard.removeObject(forKey: carryoverKey)
    super.tearDown()
  }

  func testDetectDefaultCurrencyUsesISOCurrencyCodeBeforeRegionFallback() {
    XCTAssertEqual(
      OnboardingCurrencyResolver.detectDefaultCurrency(locale: Locale(identifier: "en_CA")),
      "C$"
    )
    XCTAssertEqual(
      OnboardingCurrencyResolver.detectDefaultCurrency(locale: Locale(identifier: "en_AU")),
      "A$"
    )
    XCTAssertEqual(
      OnboardingCurrencyResolver.detectDefaultCurrency(locale: Locale(identifier: "en_SG")),
      "S$"
    )
  }

  func testDetectDefaultCurrencyHandlesSupportedEuropeanAndKroneRegions() {
    XCTAssertEqual(
      OnboardingCurrencyResolver.detectDefaultCurrency(locale: Locale(identifier: "de_DE")),
      "€"
    )
    XCTAssertEqual(
      OnboardingCurrencyResolver.detectDefaultCurrency(locale: Locale(identifier: "nb_NO")),
      "kr"
    )
    XCTAssertEqual(
      OnboardingCurrencyResolver.detectDefaultCurrency(locale: Locale(identifier: "sv_SE")),
      "kr"
    )
  }

  func testHourlyRateInputParserPreservesTwoDecimalValues() {
    XCTAssertEqual(HourlyRateInputFormatter.parse("184.54"), 184.54)
    XCTAssertEqual(HourlyRateInputFormatter.parse("184,54"), 184.54)
    XCTAssertEqual(HourlyRateInputFormatter.roundedToCents(184.545), 184.55)
  }

  func testHourlyRateInputParserHandlesGroupedDecimalValues() {
    XCTAssertEqual(HourlyRateInputFormatter.parse("1,234"), 1234)
    XCTAssertEqual(HourlyRateInputFormatter.parse("1.234"), 1234)
    XCTAssertEqual(HourlyRateInputFormatter.parse("1 234,56"), 1234.56)
    XCTAssertEqual(HourlyRateInputFormatter.parse("1,234.56"), 1234.56)
    XCTAssertEqual(HourlyRateInputFormatter.parse("1.234,56"), 1234.56)
  }

  func testDetectDefaultCurrencyHandlesExpandedSupportedCurrencies() {
    XCTAssertEqual(
      OnboardingCurrencyResolver.detectDefaultCurrency(locale: Locale(identifier: "pl_PL")),
      "zł"
    )
    XCTAssertEqual(
      OnboardingCurrencyResolver.detectDefaultCurrency(locale: Locale(identifier: "cs_CZ")),
      "Kč"
    )
    XCTAssertEqual(
      OnboardingCurrencyResolver.detectDefaultCurrency(locale: Locale(identifier: "pt_BR")),
      "R$"
    )
    XCTAssertEqual(
      OnboardingCurrencyResolver.detectDefaultCurrency(locale: Locale(identifier: "en_ZA")),
      "R"
    )
    XCTAssertEqual(
      OnboardingCurrencyResolver.detectDefaultCurrency(locale: Locale(identifier: "th_TH")),
      "฿"
    )
  }

  func testDetectDefaultCurrencyFallsBackToNorwegianLanguageThenDollar() {
    XCTAssertEqual(
      OnboardingCurrencyResolver.detectDefaultCurrency(locale: Locale(identifier: "nb_CH")),
      "kr"
    )
    XCTAssertEqual(
      OnboardingCurrencyResolver.detectDefaultCurrency(locale: Locale(identifier: "en_CH")),
      "$"
    )
  }

  func testCarryoverStoreReturnsSupportedCurrencyAndClearsInvalidCurrency() {
    OnboardingCurrencyCarryoverStore.writePreferredCurrency("€")

    XCTAssertEqual(OnboardingCurrencyCarryoverStore.readValidPreferredCurrency(), "€")

    UserDefaults.standard.set("CHF", forKey: carryoverKey)

    XCTAssertNil(OnboardingCurrencyCarryoverStore.readValidPreferredCurrency())
    XCTAssertNil(UserDefaults.standard.string(forKey: carryoverKey))
  }
}
