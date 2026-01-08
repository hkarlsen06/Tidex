import Foundation

/// Motivational salute phrases for the shift widget
/// Randomized on each widget refresh to add personality
struct MotivationalSalutes {
    /// Norwegian salutes (12 options)
    static let norwegian = [
        "God vakt!",
        "Stå på!",
        "Lykke til!",
        "Kjør på!",
        "Du klarer det!",
        "Gi gass!",
        "Full gass!",
        "Heia deg!",
        "Kos deg!",
        "Dagen er din!",
        "Vis dem!",
        "Knall og fall!",
    ]

    /// English salutes (12 options)
    static let english = [
        "Good luck!",
        "You got this!",
        "Go get 'em!",
        "Crush it!",
        "Stay strong!",
        "Make it count!",
        "Showtime!",
        "Let's go!",
        "Rock it!",
        "Go smash it!",
        "Have fun!",
        "Own it!",
    ]

    /// Returns a random salute for the given locale
    /// - Parameter locale: "no" for Norwegian, "en" for English
    /// - Returns: A random motivational phrase
    static func random(locale: String) -> String {
        let list = locale == "no" ? norwegian : english
        return list.randomElement() ?? list[0]
    }

    /// Returns all salutes for a given locale
    /// - Parameter locale: "no" for Norwegian, "en" for English
    /// - Returns: Array of all salute phrases
    static func all(locale: String) -> [String] {
        return locale == "no" ? norwegian : english
    }
}
