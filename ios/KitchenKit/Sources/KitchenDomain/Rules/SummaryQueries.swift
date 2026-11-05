import Foundation

/// Consultas de resumen mensual (bloque K2c).
///
/// Comportamiento idéntico al backend (`backend/app/services/summary_service.py`):
/// - Límites del mes calculados según la zona horaria en `settings.timezone`.
/// - `incomeCents`: pagos recibidos (`paidAt`) en el mes, de pedidos activos no cancelados.
/// - `expensesCents`: gastos activos (`spentAt`) en el mes.
/// - `netCents`: ingresos menos gastos (`incomeCents - expensesCents`).
/// - `ordersDelivered`, `ordersPending`: pedidos activos por `deliveryAt` en el mes.
/// - `salesCents`: total de pedidos entregados con `deliveryAt` en el mes.
/// - `estimatedProfitCents`: ganancia estimada de pedidos entregados con `deliveryAt` en el mes.
/// - `receivableCents`: saldo pendiente de pedidos activos no cancelados con `deliveryAt` en el mes.

public struct SummaryMonthly: Codable, Sendable, Hashable {
    public var year: Int
    public var month: Int
    public var incomeCents: Int
    public var expensesCents: Int
    public var netCents: Int
    public var ordersDelivered: Int
    public var ordersPending: Int
    public var salesCents: Int
    public var estimatedProfitCents: Int
    public var receivableCents: Int

    public init(
        year: Int,
        month: Int,
        incomeCents: Int,
        expensesCents: Int,
        netCents: Int,
        ordersDelivered: Int,
        ordersPending: Int,
        salesCents: Int,
        estimatedProfitCents: Int,
        receivableCents: Int
    ) {
        self.year = year
        self.month = month
        self.incomeCents = incomeCents
        self.expensesCents = expensesCents
        self.netCents = netCents
        self.ordersDelivered = ordersDelivered
        self.ordersPending = ordersPending
        self.salesCents = salesCents
        self.estimatedProfitCents = estimatedProfitCents
        self.receivableCents = receivableCents
    }
}

extension KitchenData {
    /// Genera el resumen mensual del negocio para un año y mes dados.
    public func monthlySummary(year: Int, month: Int) throws -> SummaryMonthly {
        guard (2000...2100).contains(year) else {
            throw DomainError.invalidValue(detail: "El año debe estar entre 2000 y 2100")
        }
        guard (1...12).contains(month) else {
            throw DomainError.invalidValue(detail: "El mes debe estar entre 1 y 12")
        }

        let tz = TimeZone(identifier: settings.timezone) ?? TimeZone(identifier: "America/Mexico_City") ?? TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz

        let startComponents = DateComponents(year: year, month: month, day: 1, hour: 0, minute: 0, second: 0)
        let nextYear = (month == 12) ? year + 1 : year
        let nextMonth = (month == 12) ? 1 : month + 1
        let endComponents = DateComponents(year: nextYear, month: nextMonth, day: 1, hour: 0, minute: 0, second: 0)

        guard let start = calendar.date(from: startComponents),
              let end = calendar.date(from: endComponents) else {
            throw DomainError.invalidValue(detail: "Fecha inválida para el resumen")
        }

        var incomeCents = 0
        for order in orders where order.isActive && order.status != .cancelado {
            for payment in order.payments {
                if payment.paidAt >= start && payment.paidAt < end {
                    incomeCents += payment.amountCents
                }
            }
        }

        var expensesCents = 0
        for expense in expenses where expense.isActive {
            if expense.spentAt >= start && expense.spentAt < end {
                expensesCents += expense.amountCents
            }
        }

        let netCents = incomeCents - expensesCents

        var ordersDelivered = 0
        var salesCents = 0
        var estimatedProfitCents = 0
        var ordersPending = 0
        var receivableCents = 0

        for order in orders where order.isActive {
            if order.deliveryAt >= start && order.deliveryAt < end {
                let totals = computeOrderTotals(order: order)

                if order.status == .entregado {
                    ordersDelivered += 1
                    salesCents += totals.totalCents
                    estimatedProfitCents += totals.profitCents
                } else if order.status == .pendiente || order.status == .enProceso {
                    ordersPending += 1
                }

                if order.status != .cancelado {
                    receivableCents += totals.balanceCents
                }
            }
        }

        return SummaryMonthly(
            year: year,
            month: month,
            incomeCents: incomeCents,
            expensesCents: expensesCents,
            netCents: netCents,
            ordersDelivered: ordersDelivered,
            ordersPending: ordersPending,
            salesCents: salesCents,
            estimatedProfitCents: estimatedProfitCents,
            receivableCents: receivableCents
        )
    }
}
