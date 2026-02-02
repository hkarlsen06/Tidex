import Foundation

/// Motivational salute phrases for the shift widget
/// Kept short to fit on one line in the widget
/// Works for shifts today, tomorrow, or in the future
struct MotivationalSalutes {
    /// Norwegian salutes - short, uplifting, time-neutral
    static let norwegian = [
        // Classic encouragements
        "God vakt!",
        "Stå på!",
        "Lykke til!",
        "Kjør på!",
        "Gi gass!",
        "Full gass!",
        "Heia deg!",
        "Kos deg!",
        "Vis dem!",
        "Du er klar!",
        "Du har dette!",
        "Slå til!",
        "Gi jern!",
        "Få det til!",
        "Nyt vakten!",
        "God energi!",
        "Bare fremover!",
        "Gled deg!",
        "La det swinge!",
        "Du rocker!",

        // Confidence boosters
        "Du er best!",
        "Helt rå!",
        "Superstjerne!",
        "Du er gull!",
        "Knallbra!",
        "Helt topp!",
        "Du fikser det!",
        "Stol på deg!",
        "Tro på deg!",
        "Du er unik!",

        // Energy & vibes
        "God stemning!",
        "Positiv vibb!",
        "Spre glede!",
        "Du lyser opp!",
        "Smil litt!",
        "Ha det gøy!",
        "Gled andre!",
        "Du inspirerer!",
        "Vær stolt!",
        "Du er viktig!",

        // Action & power
        "Full fokus!",
        "Gi alt!",
        "Vis styrke!",
        "Vær modig!",
        "Hold ut!",
        "Stå sterkt!",
        "Du takler alt!",
        "Ingenting stopper deg!",
        "Vær uredd!",
        "Du eier det!"
    ]

    /// English salutes - short, uplifting, time-neutral
    static let english = [
        // Classic encouragements
        "Good luck!",
        "You got this!",
        "Go get 'em!",
        "Crush it!",
        "Let's go!",
        "Rock it!",
        "Own it!",
        "Slay!",
        "Showtime!",
        "Have fun!",
        "Stay sharp!",
        "Kill it!",
        "Make it count!",
        "Stay golden!",
        "Be great!",
        "Boss mode!",
        "Go hard!",
        "Send it!",
        "Nail it!",
        "Smash it!",

        // Confidence boosters
        "You're the best!",
        "Superstar!",
        "You're gold!",
        "Amazing!",
        "Legendary!",
        "You're a pro!",
        "Trust yourself!",
        "Believe!",
        "You're unique!",
        "Stay confident!",

        // Energy & vibes
        "Good vibes!",
        "Spread joy!",
        "You light it up!",
        "Keep smiling!",
        "Enjoy it!",
        "Make 'em smile!",
        "You inspire!",
        "Be proud!",
        "You matter!",
        "Stay positive!",

        // Action & power
        "Full focus!",
        "Give it all!",
        "Show strength!",
        "Be bold!",
        "Stay strong!",
        "Stand tall!",
        "You can do it!",
        "Unstoppable!",
        "Be fearless!",
        "You own it!"
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
