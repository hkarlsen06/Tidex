package no.tidex.app.features

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import no.tidex.app.utilities.TidexColors

/**
 * Native offline dashboard displayed when network is unavailable.
 *
 * Mirrors iOS OfflineScreenView functionality:
 * - Shows cached shift data
 * - Provides retry button to reload
 * - Auto-reconnects when network restored
 */
@Composable
fun OfflineScreen(
    locale: String,
    onRetry: () -> Unit
) {
    val context = LocalContext.current
    var dashboardData by remember { mutableStateOf<OfflineDashboardData?>(null) }

    // Load dashboard data on composition
    LaunchedEffect(Unit) {
        dashboardData = OfflineShiftStorage.calculateDashboardData(context)
    }

    // Localized strings
    val offlineTitle = if (locale == "no") "Ingen tilkobling" else "No Connection"
    val offlineSubtitle = if (locale == "no")
        "Kobler til automatisk når online"
    else
        "Will reconnect when online"
    val retryButtonTitle = if (locale == "no") "Prøv igjen" else "Try Again"
    val noDataMessage = if (locale == "no") "Ingen data tilgjengelig" else "No data available"

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(TidexColors.DarkBackground)
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 24.dp)
        ) {
            // Header
            HeaderSection(locale)

            Spacer(modifier = Modifier.weight(1f))

            // Status message
            StatusSection(offlineTitle, offlineSubtitle)

            Spacer(modifier = Modifier.weight(1f))

            // Dashboard cards or empty state
            dashboardData?.let { data ->
                if (data.hasData) {
                    DashboardCards(data, locale)
                } else {
                    EmptyStateView(noDataMessage)
                }
            } ?: EmptyStateView(noDataMessage)

            Spacer(modifier = Modifier.weight(1f))

            // Retry button
            RetryButton(retryButtonTitle, onRetry)

            Spacer(modifier = Modifier.height(50.dp))
        }
    }
}

@Composable
private fun HeaderSection(locale: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 16.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Logo and app name
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Simplified logo placeholder (would use actual vector in production)
            Box(
                modifier = Modifier
                    .size(28.dp)
                    .clip(RoundedCornerShape(6.dp))
                    .background(
                        Brush.linearGradient(
                            colors = listOf(
                                TidexColors.LogoGradientStart,
                                TidexColors.LogoGradientMid,
                                TidexColors.LogoGradientEnd
                            )
                        )
                    )
            )

            Text(
                text = "Tidex",
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold,
                color = TidexColors.TextPrimary
            )
        }

        // Offline indicator
        Icon(
            imageVector = Icons.Default.Warning,
            contentDescription = "Offline",
            tint = TidexColors.BrandBlue,
            modifier = Modifier.size(24.dp)
        )
    }
}

@Composable
private fun StatusSection(title: String, subtitle: String) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.fillMaxWidth()
    ) {
        Text(
            text = title,
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold,
            color = TidexColors.TextPrimary
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = subtitle,
            fontSize = 13.sp,
            color = TidexColors.TextMuted
        )
    }
}

@Composable
private fun DashboardCards(data: OfflineDashboardData, locale: String) {
    Column(
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        // Payroll Card
        if (data.showPreviousPayroll) {
            PayrollCard(data, locale)
        }

        // Total Card
        TotalCard(data, locale)

        // Next Shift Card
        data.nextShift?.let { shift ->
            NextShiftCard(shift, data.nextShiftIsToday, locale, data.hasTaxEnabled)
        }
    }
}

@Composable
private fun PayrollCard(data: OfflineDashboardData, locale: String) {
    val payrollLabel = if (locale == "no") "Lønning" else "Payroll"
    val grossLabel = if (locale == "no") "Brutto" else "Gross"

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = TidexColors.SurfacePrimary),
        shape = RoundedCornerShape(12.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp)
        ) {
            Text(
                text = "$payrollLabel • ${data.payrollMonth}",
                fontSize = 13.sp,
                color = TidexColors.TextMuted
            )
            Spacer(modifier = Modifier.height(8.dp))

            val displayAmount = if (data.hasTaxEnabled) data.previousMonthNet else data.previousMonthGross
            Text(
                text = OfflineShiftStorage.formatCurrency(displayAmount, data.currencySymbol, locale),
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold,
                color = TidexColors.TextPrimary
            )

            if (data.hasTaxEnabled) {
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "$grossLabel: ${OfflineShiftStorage.formatCurrency(data.previousMonthGross, data.currencySymbol, locale)}",
                    fontSize = 13.sp,
                    color = TidexColors.TextSecondary
                )
            }
        }
    }
}

@Composable
private fun TotalCard(data: OfflineDashboardData, locale: String) {
    val totalLabel = if (locale == "no") "Total denne måneden" else "Total this month"
    val shiftsLabel = if (locale == "no") "vakter" else "shifts"

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = TidexColors.SurfacePrimary),
        shape = RoundedCornerShape(12.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp)
        ) {
            Text(
                text = totalLabel,
                fontSize = 13.sp,
                color = TidexColors.TextMuted
            )
            Spacer(modifier = Modifier.height(8.dp))

            val displayAmount = if (data.hasTaxEnabled) data.currentMonthNet else data.currentMonthGross
            Text(
                text = OfflineShiftStorage.formatCurrency(displayAmount, data.currencySymbol, locale),
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold,
                color = TidexColors.TextPrimary
            )

            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "${data.currentMonthShiftCount} $shiftsLabel",
                fontSize = 13.sp,
                color = TidexColors.TextSecondary
            )
        }
    }
}

@Composable
private fun NextShiftCard(shift: StoredShift, isToday: Boolean, locale: String, hasTax: Boolean) {
    val nextLabel = if (locale == "no") "Neste vakt" else "Next shift"
    val todayLabel = if (locale == "no") "I dag" else "Today"
    val dateLabel = if (isToday) todayLabel else formatShiftDate(shift.shiftDate, locale)

    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = TidexColors.SurfacePrimary),
        shape = RoundedCornerShape(12.dp)
    ) {
        Column(
            modifier = Modifier.padding(16.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = nextLabel,
                    fontSize = 13.sp,
                    color = TidexColors.TextMuted
                )
                Text(
                    text = dateLabel,
                    fontSize = 13.sp,
                    color = if (isToday) TidexColors.BrandBlue else TidexColors.TextSecondary
                )
            }

            Spacer(modifier = Modifier.height(8.dp))

            Text(
                text = "${shift.startTime} - ${shift.endTime}",
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold,
                color = TidexColors.TextPrimary
            )

            Spacer(modifier = Modifier.height(4.dp))

            val displayAmount = if (hasTax && shift.taxRate != null) {
                shift.totalGrossEstimate * (1 - shift.taxRate)
            } else {
                shift.totalGrossEstimate
            }

            Text(
                text = OfflineShiftStorage.formatCurrency(
                    displayAmount,
                    shift.currencySymbol ?: "kr",
                    locale
                ),
                fontSize = 16.sp,
                color = TidexColors.TextSecondary
            )
        }
    }
}

@Composable
private fun EmptyStateView(message: String) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 60.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            imageVector = Icons.Default.Warning,
            contentDescription = null,
            tint = TidexColors.TextMuted.copy(alpha = 0.5f),
            modifier = Modifier.size(40.dp)
        )
        Spacer(modifier = Modifier.height(12.dp))
        Text(
            text = message,
            fontSize = 16.sp,
            fontWeight = FontWeight.Medium,
            color = TidexColors.TextSecondary
        )
    }
}

@Composable
private fun RetryButton(title: String, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .height(52.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = TidexColors.BrandBlue
        ),
        shape = RoundedCornerShape(12.dp)
    ) {
        Icon(
            imageVector = Icons.Default.Refresh,
            contentDescription = null,
            modifier = Modifier.size(20.dp)
        )
        Spacer(modifier = Modifier.width(8.dp))
        Text(
            text = title,
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold
        )
    }
}

/**
 * Format shift date for display.
 */
private fun formatShiftDate(dateString: String, locale: String): String {
    return try {
        val inputFormat = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.getDefault())
        val date = inputFormat.parse(dateString) ?: return dateString

        val outputFormat = java.text.SimpleDateFormat(
            "EEE, d MMM",
            if (locale == "no") java.util.Locale("nb", "NO") else java.util.Locale.US
        )
        outputFormat.format(date)
    } catch (e: Exception) {
        dateString
    }
}
