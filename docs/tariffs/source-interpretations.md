# Tariff source decisions

Verified on 6 November 2026. The catalogue files record the source URLs for every rate. This document records interpretations that affect calculation behavior and the limits that require employer-specific inputs.

## Preserve entitlement boundaries

HK-Virke, NHO Handelsoverenskomsten, NHO Butikkoverenskomsten, and energy stations explicitly exclude ordinary UB when overtime is paid. Their reviewed configurations retain that exclusion. Riksavtalen section 4.3.6 explicitly retains the ordinary additions during overtime without applying the overtime percentage to UB. Its reviewed configuration adds the base overtime premium and the applicable ordinary UB separately.

Sources: [HK section 14.3](https://www.virke.no/globalassets/6.tariff-og-lonn/protokoller-og-lonnssatser/landsoverenskomsten-hk/landsoverenskomsten-2024-2026-virke-hk-korrigert-14.11.2024.pdf), [Handelsoverenskomsten sections 3.9.4 and 3.11](https://hk.no/shared-files/6846/), [Butikkoverenskomsten sections 10 and 11](https://hk.no/shared-files/7703/), [energy stations section 2.6.2](https://www.virke.no/globalassets/6.tariff-og-lonn/protokoller-og-lonnssatser/bensinstasjonoversenskomsten-virkehk/energistasjonsoverkomsten-2024-2026-virke-hk2.pdf), and [Riksavtalen section 4.3.6](https://www.nhoreiseliv.no/contentassets/3b3a903b8ed84576a60df30606b3fe5b/riksavtalen-2024---2026.pdf).

Handel's exclusion is specifically section 3.9.1 ordinary UB. Section 3.9.2 holiday-eve pay continues during overtime, so it is an explicit retained subset. At level 1, an Easter Eve overtime hour is 195.80 base plus 195.80 holiday-eve pay plus 97.90 overtime, totaling 489.50. Energy stations use the equivalent distinction between sections 2.5 and 2.6. Their Easter Eve holiday payment begins at 15:00, and weekday morning overtime switches from 100% to 50% at 06:00.

## Security ordinary additions continue during overtime

The security agreement section 5.5 establishes separate night, weekend, and holiday entitlements for service in those periods. Section 6.5 specifies a 100% overtime premium during the periods covered by section 5.5 b and c, and on Saturday after noon. Section 6.6 assigns 50% to other overtime. Neither provision excludes the section 5.5 entitlement during overtime.

The reviewed interpretation therefore retains ordinary additions, sums the separate night and weekend amounts, and calculates the overtime premium on personal pay. It does not copy the HK exclusion. The holiday addition has its own fixed basis, the entry monthly wage divided by 162.5. Section 5.6 continuous shift arrangements are excluded from these presets because that section replaces section 5.5 and needs a different shift arrangement.

Regression examples use the published entry rate. Monday 21:00-23:00 with the second hour overtime totals 671.55. The corresponding Sunday shift totals 890.66. These exercise 50% and 100% overtime while retaining the applicable ordinary additions.

This is an interpretation for the reviewer to assess against the exact text. It does not establish a worker's contracted schedule, call-out entitlement, or daily overtime boundary. The catalogue notes those limits.

Sources: [security agreement sections 5 and 6](https://www.virke.no/globalassets/uploaded-files/finn-tariffavtale/vekteroverenskomsten-2024-2026-nho-service-og-handel-naf.pdf), [2026 wage table](https://www.nhosh.no/contentassets/385855c87911442eaf6c8fccaf866049/tariffbrev-2026-vekter.pdf).

Section 5.1 gives apprentices half the adult additions during their training plan. Separate apprentice presets apply half the night, weekend, and holiday payments. Work outside the training plan uses the adult starting wage and full additions. Weekly overtime uses that adult basis. Other work-plan changes require manual adjustment. For an apprentice in the first training year, an ordinary Sunday hour at 22:00 is 104.29 plus 14.00 night pay plus 24.00 weekend pay, totaling 142.29.

## Cleaning ordinary additions continue during overtime

NHO and Virke cleaning agreements establish overtime premiums in section 7 and night/weekend/holiday entitlements in section 8. The section 8 entitlements are expressed for work in the specified periods. They do not contain the explicit overtime exclusion found in the retail agreements.

The reviewed interpretation retains the applicable section 8 addition while paying section 7 overtime. Night pay is a separate group. Weekend and holiday percentage rules take the maximum within their calendar group, so a Sunday public holiday does not receive both calendar percentages. Local improvements remain outside the preset.

The regression example is Monday 21:00-23:00 at the adult starting rate with the second hour overtime. It totals 799.87 for either employer agreement. Daily overtime and notice-related pay need the actual work plan, so this example deliberately exercises the weekly calculation only.

Sources: [NHO cleaning agreement sections 7 and 8](https://arbeidsmandsforbundet.no/wp-content/uploads/2025/01/Renholdsbedrifter%E2%80%93NHO-Service-og-Handel%E2%80%93overenskomst-2024-2026.pdf), [Virke cleaning agreement sections 7 and 8](https://www.virke.no/globalassets/6.tariff-og-lonn/tariffavtaler/renholdsoverenskomsten-2024-2026-virke-naf.pdf).

Both agreements set an adult unskilled minimum for apprentice overtime. Separate 37.5-hour apprentice presets use 133.08 for ordinary hours and 247.29 for the whole overtime hour, including its premium and percentage additions. An ordinary weekday overtime hour therefore pays 370.935 before display rounding. Reduced-week apprentice rates were not established by the sources and are not offered.

## Riksavtalen holidays follow the start of the shift

Section 4.2.1 attaches holiday payment to a shift started on the qualifying day, including its hours after midnight. A shift that starts the previous day does not gain the holiday entitlement merely by crossing midnight. The catalogue uses explicit shift-start restrictions. Holiday eves start at 15:00 and carry into the following day for qualifying shifts.

The section contains an exception for night guards starting after midnight on the following morning. Those shifts retain the holiday payment through the whole shift. An explicit original shift-start cutoff before 06:00 distinguishes a 00:00-08:00 shift on 2 January from an ordinary shift starting at 22:00 that evening. Ordinary night and holiday payments share a maximum group because section 4.3.4 excludes the ordinary addition during holiday pay.

The final rate table gives 24.87 for manual work by night guards. The earlier voting brochure says 24.84. The final table wins. This is an additional manual-work payment, not the ordinary night rate. Section 4.3.4 excludes ordinary evening, weekend, and night provisions on qualifying holidays; it does not exclude section 4.3.5 manual-work pay.

Sources: [Riksavtalen sections 4.2 and 4.3](https://www.nhoreiseliv.no/contentassets/3b3a903b8ed84576a60df30606b3fe5b/riksavtalen-2024---2026.pdf), [final 2026 rate table](https://www.fellesforbundet.no/globalassets/lonn-og-tariffsaker/tariffavtaler/overenskomster-20262028/satser-landsoverenskomst-fra-1.-juni-2026.pdf).

## Public-sector hourly equivalents and overtime bases differ

KS chapter 4 uses published annual minima divided by the annual hours for the selected weekly schedule. Teaching is excluded because its hourly conversion uses a separate formula. The revised ordinary supplements apply from October. Night extension past 06:00 is not applied indiscriminately to morning work.

The master's degree plus additional qualification row is for teaching roles. It is excluded from all non-teaching KS presets, rather than relabeled as a general non-teaching qualification.

PBL ordinary hourly pay uses annual salary divided by 1950. Its overtime premium uses annual salary divided by 1850. The premium multiplier changes only the overtime addition; it does not change the ordinary base wage. KS uses the same 1850 premium divisor for non-teaching roles.

Holiday overtime is 133 1/3%, including Easter Eve and specified eves from noon. Dated overtime windows implement those boundaries. A generic weekday 50% or public-holiday 100% would be wrong. KS rota overtime depends on time before and after the contracted shift, so automatic rota overtime is disabled. The catalogue explicitly calls for manual adjustment there.

Sources: [KS agreement sections 5, 6, 12.3, and chapter 4](https://www.ks.no/globalassets/fagomrader/lonn-og-tariff/tariff-2024/hovedtariffavtalen-2026-2028---interaktiv-til-nettsiden.pdf), [KS October implementation guidance](https://www.ks.no/fagomrader/lonn-og-tariff/hovedtariffavtalen/endringer-i-tilleggene-i-hta-kapittel-1--5-fra-forste-oktober/), [PBL sections 5, 6, and 17.3](https://pbl.no/tariff-og-loenn/hovedavtale-og-hovedtariffavtale-2024-2026).

## No inferred historical compensation

The reviewed catalogue activates on 6 November. Its legal effective dates remain in metadata. New future wage setup and past compensation are different operations. HK already received a separate backpay operation. NHO security, NHO cleaning, NHO Handelsoverenskomsten, Butikkoverenskomsten, and energy-station protocols contain historical allowance or eligibility exclusions. A rate difference alone cannot establish the amount owed.

The maintenance command prepares read-only proposals, retains higher saved base pay, and requires an explicit source revision. It never chooses a worker's qualification, overwrites custom supplements, or edits historical snapshots.
