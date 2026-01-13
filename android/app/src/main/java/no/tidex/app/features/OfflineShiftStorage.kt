package no.tidex.app.features

import android.content.Context
import com.google.gson.Gson
import com.google.gson.annotations.SerializedName
import com.google.gson.reflect.TypeToken
import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Data class matching the StoredShift structure from iOS and TypeScript.
 */
data class StoredShift(
    @SerializedName("shiftId") val shiftId: String,
    @SerializedName("shiftDate") val shiftDate: String, // YYYY-MM-DD
    @SerializedName("startTime") val startTime: String, // HH:mm
    @SerializedName("endTime") val endTime: String, // HH:mm
    @SerializedName("hourlyWage") val hourlyWage: Double,
    @SerializedName("supplementRatePerHour") val supplementRatePerHour: Double,
    @SerializedName("totalGrossEstimate") val totalGrossEstimate: Double,
    @SerializedName("locale") val locale: String,
    @SerializedName("currencySymbol") val currencySymbol: String? = "kr",
    @SerializedName("taxRate") val taxRate: Double? = null
)

/**
 * Dashboard data calculated from cached shifts.
 */
data class OfflineDashboardData(
    val hasData: Boolean,
    val currentMonthGross: Double,
    val currentMonthNet: Double,
    val currentMonthShiftCount: Int,
    val plannedShiftsCount: Int,
    val previousMonthGross: Double,
    val previousMonthNet: Double,
    val previousMonthTax: Double,
    val projectedTotal: Double,
    val percentageChange: Double,
    val hasTaxEnabled: Boolean,
    val hasPayout: Boolean,
    val payrollDay: Int,
    val payrollMonth: String,
    val showPreviousPayroll: Boolean,
    val nextShift: StoredShift?,
    val nextShiftIsToday: Boolean,
    val currencySymbol: String
)

/**
 * Utility for reading and calculating dashboard data from cached shifts.
 * Mirrors iOS OfflineShiftStorage functionality.
 */
object OfflineShiftStorage {
    private const val PREFS_NAME = "tidex_shifts"
    private const val SHIFTS_KEY = "upcoming_shifts"
    private val gson = Gson()
    private val dateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
    private val timeFormat = SimpleDateFormat("HH:mm", Locale.getDefault())

    /**
     * Load shifts from SharedPreferences.
     */
    fun loadShifts(context: Context): List<StoredShift> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val json = prefs.getString(SHIFTS_KEY, null) ?: return emptyList()

        return try {
            val type = object : TypeToken<List<StoredShift>>() {}.type
            gson.fromJson(json, type)
        } catch (e: Exception) {
            emptyList()
        }
    }

    /**
     * Calculate dashboard data from cached shifts.
     */
    fun calculateDashboardData(context: Context): OfflineDashboardData {
        val shifts = loadShifts(context)

        if (shifts.isEmpty()) {
            return OfflineDashboardData(
                hasData = false,
                currentMonthGross = 0.0,
                currentMonthNet = 0.0,
                currentMonthShiftCount = 0,
                plannedShiftsCount = 0,
                previousMonthGross = 0.0,
                previousMonthNet = 0.0,
                previousMonthTax = 0.0,
                projectedTotal = 0.0,
                percentageChange = 0.0,
                hasTaxEnabled = false,
                hasPayout = false,
                payrollDay = 12,
                payrollMonth = "",
                showPreviousPayroll = false,
                nextShift = null,
                nextShiftIsToday = false,
                currencySymbol = "kr"
            )
        }

        val now = Calendar.getInstance()
        val currentMonth = now.get(Calendar.MONTH)
        val currentYear = now.get(Calendar.YEAR)
        val today = dateFormat.format(now.time)

        // Calculate previous month
        val prevMonth = Calendar.getInstance().apply {
            add(Calendar.MONTH, -1)
        }
        val prevMonthNum = prevMonth.get(Calendar.MONTH)
        val prevMonthYear = prevMonth.get(Calendar.YEAR)

        // Group shifts by month
        var currentMonthGross = 0.0
        var previousMonthGross = 0.0
        var currentMonthCount = 0
        var plannedCount = 0

        val firstShift = shifts.firstOrNull()
        val taxRate = firstShift?.taxRate ?: 0.0
        val hasTax = taxRate > 0
        val currencySymbol = firstShift?.currencySymbol ?: "kr"

        for (shift in shifts) {
            val shiftDate = try {
                dateFormat.parse(shift.shiftDate)
            } catch (e: Exception) {
                continue
            } ?: continue

            val shiftCal = Calendar.getInstance().apply { time = shiftDate }
            val shiftMonth = shiftCal.get(Calendar.MONTH)
            val shiftYear = shiftCal.get(Calendar.YEAR)

            if (shiftYear == currentYear && shiftMonth == currentMonth) {
                currentMonthGross += shift.totalGrossEstimate
                currentMonthCount++
                if (shift.shiftDate >= today) {
                    plannedCount++
                }
            } else if (shiftYear == prevMonthYear && shiftMonth == prevMonthNum) {
                previousMonthGross += shift.totalGrossEstimate
            }
        }

        val currentMonthNet = if (hasTax) currentMonthGross * (1 - taxRate) else currentMonthGross
        val previousMonthNet = if (hasTax) previousMonthGross * (1 - taxRate) else previousMonthGross
        val previousMonthTax = if (hasTax) previousMonthGross * taxRate else 0.0

        // Find next upcoming shift
        val nextShift = shifts
            .filter { it.shiftDate >= today }
            .minByOrNull { it.shiftDate + it.startTime }

        val nextShiftIsToday = nextShift?.shiftDate == today

        // Calculate percentage change
        val percentageChange = if (previousMonthGross > 0) {
            ((currentMonthGross - previousMonthGross) / previousMonthGross) * 100
        } else {
            0.0
        }

        // Get payroll month name
        val monthFormatter = SimpleDateFormat("MMMM", Locale.getDefault())
        val payrollMonth = monthFormatter.format(prevMonth.time)

        return OfflineDashboardData(
            hasData = true,
            currentMonthGross = currentMonthGross,
            currentMonthNet = currentMonthNet,
            currentMonthShiftCount = currentMonthCount,
            plannedShiftsCount = plannedCount,
            previousMonthGross = previousMonthGross,
            previousMonthNet = previousMonthNet,
            previousMonthTax = previousMonthTax,
            projectedTotal = currentMonthNet,
            percentageChange = percentageChange,
            hasTaxEnabled = hasTax,
            hasPayout = previousMonthGross > 0,
            payrollDay = 12,
            payrollMonth = payrollMonth.replaceFirstChar { it.uppercase() },
            showPreviousPayroll = previousMonthGross > 0,
            nextShift = nextShift,
            nextShiftIsToday = nextShiftIsToday,
            currencySymbol = currencySymbol
        )
    }

    /**
     * Format currency value.
     */
    fun formatCurrency(amount: Double, symbol: String, locale: String): String {
        val formatter = NumberFormat.getInstance(
            if (locale == "no") Locale("nb", "NO") else Locale.US
        )
        formatter.maximumFractionDigits = 0
        return "${formatter.format(amount)} $symbol"
    }
}
