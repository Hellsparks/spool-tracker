<!--
  SpoolTrackerPanel.vue
  Installed to: ~/mainsail-src/src/components/panels/SpoolTrackerPanel.vue
  by install.sh — do not edit there directly, edit here and re-run install.sh
-->
<template>
    <panel
        :title="$t('SpoolTracker.Title')"
        icon="mdi-weight"
        card-class="spool-tracker-panel"
    >
        <template #buttons>
            <v-btn icon tile :title="$t('SpoolTracker.AddSpool')" @click="addSpool">
                <v-icon>mdi-plus</v-icon>
            </v-btn>
        </template>

        <v-simple-table dense>
            <thead>
                <tr>
                    <th class="text-left">{{ $t('SpoolTracker.Name') }}</th>
                    <th class="text-right">{{ $t('SpoolTracker.SpoolWeight') }}</th>
                    <th class="text-right">{{ $t('SpoolTracker.Measured') }}</th>
                    <th class="text-right">{{ $t('SpoolTracker.Filament') }}</th>
                    <th></th>
                </tr>
            </thead>
            <tbody>
                <tr v-for="(spool, i) in spools" :key="spool.id">
                    <td>
                        <v-text-field
                            v-model="spool.name"
                            dense hide-details flat solo
                            @change="persist"
                        />
                    </td>

                    <!-- Empty spool tare weight — input like a temperature setpoint -->
                    <td style="width: 120px">
                        <v-text-field
                            v-model.number="spool.spoolWeight"
                            type="number" min="0" step="1"
                            suffix="g"
                            dense hide-details flat solo reverse
                            @change="persist"
                        />
                    </td>

                    <!-- Live weight from Klipper printer object -->
                    <td class="text-right" style="width: 110px; font-variant-numeric: tabular-nums">
                        <span :class="measuredClass(i)">{{ fmt(measuredWeights[i]) }}</span>
                    </td>

                    <!-- Filament remaining = measured − tare -->
                    <td class="text-right" style="width: 110px; font-variant-numeric: tabular-nums">
                        <span :class="filamentClass(i)">{{ fmtFilament(i) }}</span>
                    </td>

                    <td class="text-no-wrap" style="width: 72px">
                        <!-- Tare button: zeroes this load cell channel -->
                        <v-btn
                            icon small
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

                <tr v-if="spools.length === 0">
                    <td colspan="5" class="text-center text--disabled py-4">
                        {{ $t('SpoolTracker.Empty') }}
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
    spoolWeight: number
}

@Component({ components: { Panel } })
export default class SpoolTrackerPanel extends Vue {
    spools: SpoolConfig[] = []
    taringChannel: number | null = null

    // ── Klipper printer object ────────────────────────────────────────────────

    get klipperObj(): Record<string, unknown> {
        return (this.$store.state.printer.printer?.spool_tracker ?? {}) as Record<string, unknown>
    }

    get measuredWeights(): (number | undefined)[] {
        const w = this.klipperObj.weights
        return Array.isArray(w) ? (w as number[]) : []
    }

    // ── Formatting ────────────────────────────────────────────────────────────

    fmt(v: number | undefined): string {
        return v != null ? `${v.toFixed(1)} g` : '—'
    }

    fmtFilament(i: number): string {
        const m = this.measuredWeights[i]
        const tare = this.spools[i]?.spoolWeight ?? 0
        if (m == null) return '—'
        return `${(m - tare).toFixed(1)} g`
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
            await this.$store.dispatch('printer/sendGcodeScript', `SPOOL_TARE CHANNEL=${channel}`)
        } finally {
            setTimeout(() => {
                if (this.taringChannel === channel) this.taringChannel = null
            }, 800)
        }
    }

    // ── Persistence via Moonraker DB ─────────────────────────────────────────

    persist() {
        this.$store.dispatch('gui/saveDbValue', {
            name: 'spoolTracker',
            value: { spools: this.spools },
        })
    }

    mounted() {
        const saved = this.$store.state.gui?.spoolTracker?.spools
        if (Array.isArray(saved)) this.spools = saved
    }
}
</script>
