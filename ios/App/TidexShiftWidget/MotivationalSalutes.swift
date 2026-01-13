import Foundation

/// Motivational salute phrases for the shift widget
/// Randomized on each widget refresh to add personality
struct MotivationalSalutes {
    /// Norwegian salutes (40 options)
    static let norwegian = [
        // Classic encouragements
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
        "Du er klar!",

        // Confidence boosters
        "Du er superstjerne!",
        "Bare vær deg selv!",
        "Du er fantastisk!",
        "Tro på deg selv!",
        "Du har dette!",
        "Stol på deg selv!",
        "Du er unik!",
        "Du gjør en forskjell!",

        // Action-oriented
        "Ta dagen!",
        "Grip mulighetene!",
        "Gjør det beste av det!",
        "Skap magi i dag!",
        "Slå til!",
        "Gi jern!",
        "Få det til!",
        "Vis hva du kan!",

        // Positive vibes
        "Ha en fin dag!",
        "Nyt vakten!",
        "Smil og vær glad!",
        "Spre god stemning!",
        "Du lyser opp!",
        "God energi!",
        "Positiv vibb!",
        "Du inspirerer!",

        // Empowerment
        "Du er sterkere enn du tror!",
        "Ingenting stopper deg!",
        "Du takler alt!",
        "Bare fremover!",
    ]

    /// English salutes (40 options)
    static let english = [
        // Classic encouragements
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

        // Confidence boosters
        "You're a rockstar!",
        "Just be you!",
        "You're amazing!",
        "Believe in yourself!",
        "Trust yourself!",
        "You're one of a kind!",
        "You make a difference!",
        "You're a legend!",

        // Action-oriented
        "Seize the day!",
        "Grab the moment!",
        "Make it happen!",
        "Create some magic!",
        "Time to shine!",
        "Show them what you've got!",
        "Bring your A-game!",
        "Make today great!",

        // Positive vibes
        "Have a great day!",
        "Enjoy your shift!",
        "Smile and shine!",
        "Spread good vibes!",
        "You light up the room!",
        "Stay positive!",
        "Good energy!",
        "You inspire others!",

        // Empowerment
        "You're stronger than you think!",
        "Nothing can stop you!",
        "You can handle anything!",
        "Keep pushing forward!",
        "Today is your day!",
        "Be unstoppable!",
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
