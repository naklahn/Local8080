import { writeFile } from 'node:fs/promises';

const HORIZONS_URL = 'https://ssd.jpl.nasa.gov/api/horizons.api';
const REPRESENTATIVE_LONGITUDE = -98.5795;
const REPRESENTATIVE_LATITUDE = 39.8283;
const AU_TO_KM = 149597870.7;
const NEAR_PERIGEE_KM = 363104;
const NEAR_APOGEE_KM = 405696;

function formatDate(date) {
    return date.toISOString().slice(0, 10);
}

function formatMonthDay(date) {
    return date.toLocaleDateString('en-US', {
        month: 'short',
        day: 'numeric',
        timeZone: 'UTC'
    }).toUpperCase();
}

function parseHorizonsDate(value) {
    const text = String(value || '').trim();
    const match = text.match(/^(\d{4})-([A-Za-z]{3})-(\d{1,2})\s+(\d{1,2}):(\d{2})/);

    if (!match) {
        return null;
    }

    const monthIndex = {
        JAN: 0, FEB: 1, MAR: 2, APR: 3,
        MAY: 4, JUN: 5, JUL: 6, AUG: 7,
        SEP: 8, OCT: 9, NOV: 10, DEC: 11
    }[match[2].toUpperCase()];

    if (monthIndex === undefined) {
        return null;
    }

    return new Date(Date.UTC(
        Number(match[1]),
        monthIndex,
        Number(match[3]),
        Number(match[4]),
        Number(match[5])
    ));
}

function parseMoonSnapshots(resultText) {
    const lines = String(resultText || '')
        .split(/\r?\n/)
        .map(line => line.trim());

    const headerIndex = lines.findIndex(line => line.startsWith('Date__(UT)__HR:MN,'));
    const startIndex = lines.findIndex(line => line === '$$SOE');
    const endIndex = lines.findIndex(line => line === '$$EOE');

    if (headerIndex < 0 || startIndex < 0 || endIndex <= startIndex) {
        return [];
    }

    const headers = lines[headerIndex].split(',').map(value => value.trim());
    const dateIndex = headers.indexOf('Date__(UT)__HR:MN');
    const illuminationIndex = headers.indexOf('Illu%');
    const distanceIndex = headers.indexOf('delta');

    if (dateIndex < 0 || illuminationIndex < 0 || distanceIndex < 0) {
        return [];
    }

    return lines
        .slice(startIndex + 1, endIndex)
        .map(line => {
            const values = line.split(',').map(value => value.trim());
            const date = parseHorizonsDate(values[dateIndex]);
            const illuminationPercent = Number(values[illuminationIndex]);
            const distanceAu = Number(values[distanceIndex]);

            return {
                date,
                illuminationPercent: Number.isFinite(illuminationPercent) ? illuminationPercent : null,
                distanceKm: Number.isFinite(distanceAu) ? distanceAu * AU_TO_KM : null
            };
        })
        .filter(snapshot =>
            snapshot.date instanceof Date &&
            !Number.isNaN(snapshot.date.getTime()) &&
            Number.isFinite(snapshot.illuminationPercent) &&
            Number.isFinite(snapshot.distanceKm)
        );
}

function findClosestSnapshot(snapshots, targetDate) {
    return snapshots.reduce((closest, snapshot) => {
        if (!closest) {
            return snapshot;
        }

        return Math.abs(snapshot.date - targetDate) < Math.abs(closest.date - targetDate)
            ? snapshot
            : closest;
    }, null);
}

function calculateMoonSizePercent(distanceKm) {
    const ratio = (NEAR_APOGEE_KM - distanceKm) / (NEAR_APOGEE_KM - NEAR_PERIGEE_KM);
    return Math.max(0, Math.min(100, ratio * 100));
}

function getMoonPhase(illuminationPercent, previousIlluminationPercent, nextIlluminationPercent) {
    const isWaxing = nextIlluminationPercent >= previousIlluminationPercent;

    if (illuminationPercent < 2) return 'NEW MOON';
    if (illuminationPercent > 98) return 'FULL MOON';
    if (illuminationPercent < 48) return isWaxing ? 'WAXING CRESCENT' : 'WANING CRESCENT';
    if (illuminationPercent < 52) return isWaxing ? 'FIRST QUARTER' : 'LAST QUARTER';
    return isWaxing ? 'WAXING GIBBOUS' : 'WANING GIBBOUS';
}

const now = new Date();
const startDate = new Date(now);
startDate.setUTCDate(startDate.getUTCDate() - 1);

const stopDate = new Date(now);
stopDate.setUTCDate(stopDate.getUTCDate() + 60);

const params = new URLSearchParams({
    format: 'json',
    COMMAND: "'301'",
    OBJ_DATA: "'NO'",
    MAKE_EPHEM: "'YES'",
    EPHEM_TYPE: "'OBSERVER'",
    CENTER: "'coord@399'",
    COORD_TYPE: "'GEODETIC'",
    SITE_COORD: `'${REPRESENTATIVE_LONGITUDE},${REPRESENTATIVE_LATITUDE},0'`,
    START_TIME: `'${formatDate(startDate)}'`,
    STOP_TIME: `'${formatDate(stopDate)}'`,
    STEP_SIZE: "'6h'",
    CSV_FORMAT: "'YES'"
});

const response = await fetch(`${HORIZONS_URL}?${params.toString()}`);

if (!response.ok) {
    throw new Error(`NASA Horizons request failed: ${response.status}`);
}

const payload = await response.json();

if (payload.error) {
    throw new Error(`NASA Horizons error: ${payload.error}`);
}

const snapshots = parseMoonSnapshots(payload.result);

if (snapshots.length < 3) {
    throw new Error('NASA Horizons returned insufficient moon data.');
}

const currentIndex = snapshots.reduce((closestIndex, snapshot, index) => {
    const closestDistance = Math.abs(snapshots[closestIndex].date - now);
    const distance = Math.abs(snapshot.date - now);
    return distance < closestDistance ? index : closestIndex;
}, 0);

const current = snapshots[currentIndex];
const previous = snapshots[Math.max(0, currentIndex - 1)];
const next = snapshots[Math.min(snapshots.length - 1, currentIndex + 1)];

const fullMoonCandidates = snapshots
    .filter(snapshot => snapshot.illuminationPercent > 99)
    .filter(snapshot => snapshot.date >= now)
    .sort((first, second) => first.date - second.date);

const nextFullMoon = fullMoonCandidates[0] || null;

const moonData = {
    updatedAt: now.toISOString(),
    source: 'NASA/JPL Horizons',
    currentIlluminationPercent: Number(current.illuminationPercent.toFixed(1)),
    currentSizePercent: Number(calculateMoonSizePercent(current.distanceKm).toFixed(1)),
    currentPhaseName: getMoonPhase(
        current.illuminationPercent,
        previous.illuminationPercent,
        next.illuminationPercent
    ),
    nextMajorPhaseName: nextFullMoon ? 'FULL MOON' : '--',
    nextMajorPhaseDateText: nextFullMoon ? formatMonthDay(nextFullMoon.date) : '--',
    nextSuperMoonText: nextFullMoon ? formatMonthDay(nextFullMoon.date) : '--'
};

await writeFile(
    'moon-data.json',
    `${JSON.stringify(moonData, null, 2)}\n`,
    'utf8'
);

console.log('Updated moon-data.json:', moonData);