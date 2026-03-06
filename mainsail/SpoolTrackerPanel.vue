<!--
  SpoolTrackerPanel.vue — Mainsail panel for multi-spool load cell tracking

  Deploy to: src/components/panels/SpoolTrackerPanel.vue

  Then register the panel in your dashboard view, e.g. src/views/Dashboard.vue:
    import SpoolTrackerPanel from '@/components/panels/SpoolTrackerPanel.vue'
    <spool-tracker-panel v-if="..." />

  Requires spool_tracker.py Klipper extra to be running.
-->
<template>
    <panel
        :title="$t('SpoolTracker.Title', 'Spool Tracker')"
        icon="mdi-weight"
        card-class="spool-tracker-panel"
    >
        <template #buttons>
            <v-btn icon tile :title="$t('SpoolTracker.AddSpool', 'Add spool')" @click="addSpool">
                <v-icon>mdi-plus</v-icon>
            </v-btn>
        </template>

        <v-simple-table dense>
            <thead>
                <tr>
                    <th class="text-left">{{ $t('SpoolTracker.Name', 'Name') }}</th>
                    <th class="text-right">{{ $t('SpoolTracker.SpoolWeight', 'Spool (g)') }}</th>
                    <th class="text-right">{{ $t('SpoolTracker.Measured', 'Measured (g)') }}</th>
                    <th class="text-right">{{ $t('SpoolTracker.Filament', 'Filament (g)') }}</th>
                    <th></th>
                </tr>
            </thead>
            <tbody>
                <tr v-for="(spool, i) in spools" :key="spool.id">
                    <!-- Name -->
                    <td>
                        <v-text-field
                            v-model="spool.name"
                            dense
                            hide-details
                            flat
                            solo
                            @change="persist"
                        />
                    </td>

                    <!-- Spool (tare) weight — input like temperature setpoint -->
                    <td class="text-right" style="width: 110px">
                        <v-text-field
                            v-model.number="spool.spoolWeight"
                            type="number"
                            min="0"
                            step="1"
                            suffix="g"
                            dense
                            hide-details
                            flat
                            solo
                            reverse
                            @change="persist"
                        />
                    </td>

                    <!-- Live measured weight from MCU -->
                    <td class="text-right" style="width: 110px">
                        <span :class="measuredClass(i)">
                            {{ fmt(measuredWeights[i]) }}
                        </span>
                    </td>

                    <!-- Calculated filament remaining -->
                    <td class="text-right" style="width: 110px">
                        <span :class="filamentClass(i)">
                            {{ fmtFilament(i) }}
                        </span>
                    </td>

                    <!-- Tare + Delete -->
                    <td class="text-no-wrap" style="width: 80px">
                        <v-btn
                            icon
                            small
                            :title="`Tare channel ${i}`"
                            :loading="taringChannel === i"
                            @click="tare(i)"
                        >
                            <v-icon small>mdi-scale-balance</v-icon>
                        </v-btn>
                        <v-btn icon small @click="removeSpool(i)">
                            <v-icon small>mdi-delete-outline</v-icon>
                        </v-btn>
                    </td>
                </tr>

                <!-- Empty state -->
                <tr v-if="spools.length === 0">
                    <td colspan="5" class="text-center text--disabled py-4">
                        {{ $t('SpoolTracker.Empty', 'No spools configured — click + to add one') }}
                    </td>
                </tr>
            </tbody>
        </v-simple-table>
    </panel>
</template>

<script lang="ts">
import { Component, Vue } from 'vue-property-decorator'
import Panel from '@/components/ui/Panel.vue'

interface SpoolConfig {
    id: string
    name: string
    spoolWeight: number // grams — empty spool tare weight
}

const DB_NS = 'mainsail'
const DB_KEY = 'spoolTracker.spools'

@Component({ components: { Panel } })
export default class SpoolTrackerPanel extends Vue {
    spools: SpoolConfig[] = []
    taringChannel: number | null = null

    // ── Klipper data ─────────────────────────────────────────────────────────

    get klipperObj(): Record<string, unknown> {
        return (this.$store.getters['printer/getPrinterObject']('spool_tracker') ?? {}) as Record<
            string,
            unknown
        >
    }

    get measuredWeights(): (number | undefined)[] {
        const w = this.klipperObj.weights
        return Array.isArray(w) ? (w as number[]) : []
    }

    // ── Formatting ────────────────────────────────────────────────────────────

    fmt(v: number | undefined): string {
        return v != null ? v.toFixed(1) : '—'
    }

    fmtFilament(i: number): string {
        const m = this.measuredWeights[i]
        const tare = this.spools[i]?.spoolWeight ?? 0
        if (m == null) return '—'
        return (m - tare).toFixed(1)
    }

    measuredClass(i: number): Record<string, boolean> {
        return { 'error--text': this.measuredWeights[i] == null }
    }

    filamentClass(i: number): Record<string, boolean> {
        const m = this.measuredWeights[i]
        const tare = this.spools[i]?.spoolWeight ?? 0
        const f = m != null ? m - tare : null
        return {
            'warning--text': f != null && f >= 0 && f < 150,
            'error--text': f != null && f < 0,
        }
    }

    // ── Spool management ─────────────────────────────────────────────────────

    addSpool() {
        this.spools.push({
            id: Date.now().toString(),
            name: `Spool ${this.spools.length + 1}`,
            spoolWeight: 250,
        })
        this.persist()
    }

    removeSpool(i: number) {
        this.spools.splice(i, 1)
        this.persist()
    }

    // ── Tare ─────────────────────────────────────────────────────────────────

    async tare(channel: number) {
        this.taringChannel = channel
        try {
            await this.$store.dispatch('server/sendGcode', `SPOOL_TARE CHANNEL=${channel}`)
        } finally {
            // Brief visual feedback before clearing spinner
            setTimeout(() => {
                if (this.taringChannel === channel) this.taringChannel = null
            }, 800)
        }
    }

    // ── Persistence (Moonraker DB) ────────────────────────────────────────────

    persist() {
        this.$store.dispatch('server/updateDatabaseItem', {
            namespace: DB_NS,
            key: DB_KEY,
            value: this.spools,
        })
    }

    async mounted() {
        try {
            const saved = await this.$store.dispatch('server/getDatabaseItem', {
                namespace: DB_NS,
                key: DB_KEY,
            })
            if (Array.isArray(saved)) this.spools = saved
        } catch {
            // First run — no saved config yet, start empty
        }
    }
}
</script>

<style scoped>
.spool-tracker-panel .v-data-table td {
    vertical-align: middle;
}
</style>
