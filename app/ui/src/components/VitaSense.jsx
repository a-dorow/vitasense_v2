import { useState, useRef, useEffect, useCallback } from "react";
import vitasenseLogo from "../assets/VitaSense_Logo.png";

const RECORD_SECONDS = 20;
const API_BASE = "http://localhost:6767";

const STATES = {
  IDLE:       "idle",
  ALIGNING:   "aligning",
  RECORDING:  "recording",
  PROCESSING: "processing",
  RESULTS:    "results",
  ERROR:      "error",
};

// Normalise a value to 0..1 within [min, max]
function norm(val, min, max) {
  if (val == null || !isFinite(val)) return 0;
  return Math.max(0, Math.min(1, (val - min) / (max - min)));
}

// Convert polar (angle, radius) to SVG cartesian coords
// angle 0 = top, clockwise
function polar(cx, cy, r, angleDeg) {
  const rad = ((angleDeg - 90) * Math.PI) / 180;
  return [cx + r * Math.cos(rad), cy + r * Math.sin(rad)];
}

// Build SVG polygon points string from normalised values [0..1] and axes config
function radarPoints(values, cx, cy, maxR, axes) {
  return axes
    .map((_, i) => {
      const angle = (360 / axes.length) * i;
      const r = values[i] * maxR;
      return polar(cx, cy, r, angle).join(",");
    })
    .join(" ");
}

const RADAR_AXES = [
  { key: "hr_bpm",   label: "HR",   min: 40,  max: 180, color: "#ff6b00",
    unit: "bpm",   normalRange: "60–100",  description: "Heart Rate" },
  { key: "spo2_pct", label: "SpO₂", min: 85,  max: 100, color: "#00d4ff",
    unit: "%",    normalRange: "95–100",  description: "Blood Oxygen" },
  { key: "sbp_mean", label: "SBP",  min: 70,  max: 180, color: "#00ff88",
    unit: "mmHg", normalRange: "90–120",  description: "Systolic BP" },
  { key: "dbp_mean", label: "DBP",  min: 40,  max: 120, color: "#a78bfa",
    unit: "mmHg", normalRange: "60–80",   description: "Diastolic BP" },
];

// ── Radar SVG component ───────────────────────────────────────────────────────
function RadarChart({ vitals }) {
  const cx = 230, cy = 230, maxR = 160;
  const n = RADAR_AXES.length;

  const values = RADAR_AXES.map(({ key, min, max }) =>
    norm(vitals[key], min, max)
  );

  const rings = [0.25, 0.5, 0.75, 1.0];

  // Normal range ring — maps normal midpoint to radar
  const normalValues = RADAR_AXES.map(({ min, max, normalRange }) => {
    const [lo, hi] = normalRange.split("–").map(Number);
    const mid = (lo + hi) / 2;
    return norm(mid, min, max);
  });

  const spokes = RADAR_AXES.map((_, i) => {
    const angle = (360 / n) * i;
    return polar(cx, cy, maxR, angle);
  });

  const filledPts  = radarPoints(values, cx, cy, maxR, RADAR_AXES);
  const normalPts  = radarPoints(normalValues, cx, cy, maxR, RADAR_AXES);

  const labelPts = RADAR_AXES.map((axis, i) => {
    const angle = (360 / n) * i;
    const [lx, ly] = polar(cx, cy, maxR + 42, angle);
    return { ...axis, lx, ly };
  });

  return (
    <svg
      viewBox="0 0 460 460"
      width="460"
      height="460"
      className="radar-svg"
    >
      {/* Grid rings */}
      {rings.map((r, ri) => (
        <polygon
          key={ri}
          points={radarPoints(Array(n).fill(r), cx, cy, maxR, RADAR_AXES)}
          fill="none"
          stroke="#00d4ff"
          strokeWidth="1.2"
          opacity={ri === rings.length - 1 ? 0.6 : 0.25}
        />
      ))}

      {/* Normal range reference polygon */}
      <polygon
        points={normalPts}
        fill="#00ff8815"
        stroke="#00ff88"
        strokeWidth="1.5"
        strokeDasharray="6 4"
        opacity="0.7"
      />

      {/* Spokes */}
      {spokes.map(([sx, sy], i) => (
        <line
          key={i}
          x1={cx} y1={cy} x2={sx} y2={sy}
          stroke="#ff6b00"
          strokeWidth="1.5"
          opacity="0.8"
        />
      ))}

      {/* Filled area */}
      <polygon
        points={filledPts}
        fill="#00ff88"
        fillOpacity="0.28"
        stroke="#00d4ff"
        strokeWidth="3"
        strokeLinejoin="round"
        className="radar-fill"
      />

      {/* Axis dots */}
      {RADAR_AXES.map(({ color }, i) => {
        const angle = (360 / n) * i;
        const r = values[i] * maxR;
        const [dx, dy] = polar(cx, cy, r, angle);
        return (
          <circle
            key={i}
            cx={dx} cy={dy} r="8"
            fill={color}
            style={{ filter: `drop-shadow(0 0 10px ${color})` }}
            className="radar-dot"
          />
        );
      })}

      {/* Labels */}
      {labelPts.map(({ label, color, lx, ly, key }, i) => {
        const val = vitals[key];
        const hasVal = val != null && isFinite(val);
        return (
          <g key={i}>
            <text
              x={lx} y={ly - 10}
              textAnchor="middle"
              dominantBaseline="middle"
              fill={color}
              fontSize="18"
              fontFamily="DM Mono, monospace"
              fontWeight="500"
              style={{ filter: `drop-shadow(0 0 10px ${color})` }}
            >
              {label}
            </text>
            {hasVal && (
              <text
                x={lx} y={ly + 14}
                textAnchor="middle"
                dominantBaseline="middle"
                fill="#f0f6ff"
                fontSize="15"
                fontFamily="DM Mono, monospace"
                fontWeight="400"
                opacity="0.95"
                style={{ filter: "drop-shadow(0 0 6px #ffffff55)" }}
              >
                {Number.isInteger(val) ? val : val.toFixed(1)}
              </text>
            )}
          </g>
        );
      })}

      {/* Center dot */}
      <circle cx={cx} cy={cy} r="4" fill="#ff6b00" opacity="0.8" />

      {/* Normal range legend — top-left corner, away from all axis labels */}
      <g>
        <line x1="12" y1="18" x2="38" y2="18" stroke="#00ff88" strokeWidth="1.5"
          strokeDasharray="4 3" opacity="0.75" />
        <text x="44" y="18" dominantBaseline="middle" fill="#00ff88" fontSize="11"
          fontFamily="DM Mono, monospace" opacity="0.75">normal range</text>
      </g>
    </svg>
  );
}

// ── Radar Legend component ────────────────────────────────────────────────────
function RadarLegend({ vitals }) {
  return (
    <div className="radar-legend">
      <p className="radar-legend-title">How to read this chart</p>
      <p className="radar-legend-desc">
        Each axis spans from its minimum (center) to maximum (outer edge).
        The <span style={{ color: "#00ff88" }}>dashed green shape</span> shows
        the normal range midpoint. Your results appear as the
        <span style={{ color: "#00d4ff" }}> solid blue shape</span> — the closer
        your result is to the outer edge on each axis, the higher that value is
        relative to its scale.
      </p>
      <div className="radar-legend-rows">
        {RADAR_AXES.map(({ key, label, color, unit, normalRange, description, min, max }) => {
          const val = vitals?.[key];
          const hasVal = val != null && isFinite(val);
          const pct = hasVal ? Math.round(norm(val, min, max) * 100) : null;
          return (
            <div key={key} className="radar-legend-row">
              <span className="radar-legend-dot" style={{ background: color, boxShadow: `0 0 8px ${color}` }} />
              <span className="radar-legend-name" style={{ color }}>{label}</span>
              <span className="radar-legend-full">{description}</span>
              <span className="radar-legend-normal">normal: {normalRange} {unit}</span>
              {hasVal && (
                <span className="radar-legend-val">
                  {Number.isInteger(val) ? val : val.toFixed(1)} {unit}
                  <span className="radar-legend-pct"> ({pct}% of scale)</span>
                </span>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}

// ── Main component ────────────────────────────────────────────────────────────
export default function VitaSense() {
  const videoRef         = useRef(null);
  const mediaRecorderRef = useRef(null);
  const chunksRef        = useRef([]);
  const streamRef        = useRef(null);
  const alignTimerRef    = useRef(null);
  const esRef            = useRef(null);

  const [appState,      setAppState]      = useState(STATES.IDLE);
  const [progress,      setProgress]      = useState(0);
  const [timeLeft,      setTimeLeft]      = useState(RECORD_SECONDS);
  const [processingMsg, setProcessingMsg] = useState("Starting pipeline...");
  const [results,       setResults]       = useState(null);
  const [partialVitals, setPartialVitals] = useState({});
  const [showRadar,     setShowRadar]     = useState(false);
  const [errorMsg,      setErrorMsg]      = useState("");
  const [faceAligned,   setFaceAligned]   = useState(false);
  const [showLegend,    setShowLegend]    = useState(false);

  // Start webcam on mount
  useEffect(() => {
    (async () => {
      try {
        const stream = await navigator.mediaDevices.getUserMedia({
          video: {
            width:      { ideal: 1280 },
            height:     { ideal: 720 },
            frameRate:  { ideal: 30, min: 24, max: 30 },
            facingMode: "user",
          },
          audio: false,
        });
        const track    = stream.getVideoTracks()[0];
        const settings = track.getSettings();
        if (settings.frameRate && settings.frameRate < 24) {
          console.warn(`[VitaSense] Camera granted ${settings.frameRate} fps — pipeline expects 30.`);
        }
        streamRef.current = stream;
        if (videoRef.current) videoRef.current.srcObject = stream;
      } catch {
        setErrorMsg("Camera access denied. Please allow camera permissions.");
        setAppState(STATES.ERROR);
      }
    })();
    return () => {
      streamRef.current?.getTracks().forEach((t) => t.stop());
      esRef.current?.abort?.();
    };
  }, []);

  // Simulate face alignment
  useEffect(() => {
    if (appState !== STATES.ALIGNING) return;
    alignTimerRef.current = setTimeout(() => setFaceAligned(true), 1500);
    return () => clearTimeout(alignTimerRef.current);
  }, [appState]);

  useEffect(() => {
    if (faceAligned && appState === STATES.ALIGNING) startRecording();
  }, [faceAligned, appState]);

  const startSession = () => {
    setFaceAligned(false);
    setResults(null);
    setPartialVitals({});
    setShowRadar(false);
    setShowLegend(false);
    setErrorMsg("");
    setAppState(STATES.ALIGNING);
  };

  const startRecording = useCallback(() => {
    if (!streamRef.current) return;
    chunksRef.current = [];

    const mr = new MediaRecorder(streamRef.current, { mimeType: "video/webm;codecs=vp8" });
    mr.ondataavailable = (e) => e.data.size > 0 && chunksRef.current.push(e.data);
    mr.onstop = handleRecordingStop;
    mediaRecorderRef.current = mr;

    setAppState(STATES.RECORDING);
    setTimeLeft(RECORD_SECONDS);
    setProgress(0);
    mr.start(250);

    let elapsed = 0;
    const tick = setInterval(() => {
      elapsed += 0.1;
      setProgress(Math.min((elapsed / RECORD_SECONDS) * 100, 100));
      setTimeLeft(Math.max(0, Math.ceil(RECORD_SECONDS - elapsed)));
      if (elapsed >= RECORD_SECONDS) {
        clearInterval(tick);
        mr.stop();
      }
    }, 100);
  }, []);

  const handleRecordingStop = async () => {
    setAppState(STATES.PROCESSING);
    setProcessingMsg("Uploading video...");

    const blob     = new Blob(chunksRef.current, { type: "video/webm" });
    const formData = new FormData();
    formData.append("video", blob, "vitasense_capture.webm");

    let job_id;
    try {
      const res = await fetch(`${API_BASE}/analyze`, { method: "POST", body: formData });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.detail || "Upload failed");
      }
      const data = await res.json();
      job_id = data.job_id;
    } catch (e) {
      setErrorMsg(e.message || "Failed to upload video.");
      setAppState(STATES.ERROR);
      return;
    }

    setProcessingMsg("Starting MATLAB pipeline...");

    const abortCtrl = new AbortController();
    esRef.current = abortCtrl;

    try {
      const sseRes = await fetch(`${API_BASE}/progress/${job_id}`, {
        signal: abortCtrl.signal,
      });

      if (!sseRes.ok) throw new Error(`SSE connection failed: ${sseRes.status}`);

      const reader  = sseRes.body.getReader();
      const decoder = new TextDecoder();
      let   buffer  = "";

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });
        const parts = buffer.split("\n\n");
        buffer = parts.pop();

        for (const part of parts) {
          if (part.startsWith(":")) continue;

          const dataLine = part.split("\n").find(l => l.startsWith("data:"));
          if (!dataLine) continue;

          try {
            const msg = JSON.parse(dataLine.slice(5).trim());

            if (msg.type === "progress") {
              setProcessingMsg(msg.message);

            } else if (msg.type === "vitals_partial") {
              setPartialVitals(prev => {
                const merged = { ...prev, ...msg };
                delete merged.type;
                return merged;
              });
              setShowRadar(true);

            } else if (msg.type === "result") {
              abortCtrl.abort();
              setPartialVitals(prev => ({ ...prev, ...msg.data }));
              setResults(msg.data);
              setShowRadar(true);
              setAppState(STATES.RESULTS);
              return;

            } else if (msg.type === "error") {
              abortCtrl.abort();
              setErrorMsg(msg.message || "Pipeline failed.");
              setAppState(STATES.ERROR);
              return;
            }
          } catch {
            // malformed JSON — skip
          }
        }
      }
    } catch (e) {
      if (e.name === "AbortError") return;
      setErrorMsg("Lost connection to server.");
      setAppState(STATES.ERROR);
    }
  };

  // ── FIX: re-attach camera stream on reset ──────────────────────────────────
  const reset = () => {
    esRef.current?.abort?.();
    setAppState(STATES.IDLE);
    setResults(null);
    setPartialVitals({});
    setShowRadar(false);
    setShowLegend(false);
    setProgress(0);
    setTimeLeft(RECORD_SECONDS);
    setFaceAligned(false);
    setErrorMsg("");
    setProcessingMsg("Starting pipeline...");

    // Re-attach the live camera stream to the video element
    if (videoRef.current && streamRef.current) {
      videoRef.current.srcObject = streamRef.current;
    }
  };

  const borderClass =
    appState === STATES.RECORDING  ? "border-recording"
    : faceAligned                  ? "border-aligned"
    : appState === STATES.ALIGNING ? "border-aligning"
    : "border-idle";

  const displayVitals = results ?? partialVitals;
  const isActive = appState === STATES.RESULTS ||
    (appState === STATES.PROCESSING && showRadar);

  return (
    <div className="vs-root">
      <div className="bg-grid" />
      <div className="bg-glow" />

      <header className="vs-header">
        <div className="logo-img-wrap">
          <img src={vitasenseLogo} alt="VitaSense" className="logo-img" />
        </div>
        <div className="header-status">
          <span className={`status-dot ${
            appState === STATES.RECORDING  ? "dot-recording"  :
            appState === STATES.PROCESSING ? "dot-processing" : "dot-idle"
          }`} />
          <span className="status-label">
            { appState === STATES.IDLE       && "Ready"      }
            { appState === STATES.ALIGNING   && "Aligning…"  }
            { appState === STATES.RECORDING  && "Recording"  }
            { appState === STATES.PROCESSING && "Analysing"  }
            { appState === STATES.RESULTS    && "Complete"   }
            { appState === STATES.ERROR      && "Error"      }
          </span>
        </div>
      </header>

      <main className="vs-main">

        {/* Left panel — HR + SpO2 */}
        <section className="vitals-section">
          <h2 className="vitals-heading">Cardiovascular</h2>
          <div className="vitals-grid">
            <VitalCard
              label="Heart Rate" unit="bpm"
              value={displayVitals?.hr_bpm}
              icon="♥" accent="#ff6b00"
              normal={[60, 100]} limits={[40, 200]}
              active={isActive}
            />
            <VitalCard
              label="SpO₂" unit="%"
              value={displayVitals?.spo2_pct}
              icon="◉" accent="#00d4ff"
              normal={[95, 100]} limits={[80, 100]}
              active={isActive}
            />
          </div>
          {appState === STATES.IDLE && (
            <div className="instructions">
              <p className="instr-title">How it works</p>
              <ol className="instr-list">
                <li>Stand <strong>50–80 cm</strong> from the camera</li>
                <li>Face the camera in <strong>good lighting</strong></li>
                <li>Remain <strong>still</strong> for 20 seconds</li>
                <li>Results appear automatically</li>
              </ol>
            </div>
          )}
          {appState === STATES.PROCESSING && (
            <div className="processing-live">
              <p className="processing-live-label">Pipeline status</p>
              <div className="processing-live-msg">{processingMsg}</div>
            </div>
          )}
        </section>

        {/* Center — Camera / Radar */}
        <section className="camera-section">
          <div className={`camera-frame ${borderClass}`}>
            <div className="corner tl"/><div className="corner tr"/>
            <div className="corner bl"/><div className="corner br"/>

            {/* Camera feed — hidden once radar appears */}
            <video
              ref={videoRef}
              autoPlay playsInline muted
              className={`camera-feed ${showRadar ? "camera-fade-out" : ""}`}
            />

            {/* Radar — fades in when first partial arrives */}
            {(showRadar || appState === STATES.RESULTS) && (
              <div className="radar-overlay radar-fade-in">
                <RadarChart vitals={partialVitals} />
                {appState === STATES.PROCESSING && (
                  <p className="radar-processing-label">{processingMsg}</p>
                )}
              </div>
            )}

            {/* Alignment overlay */}
            {(appState === STATES.IDLE || appState === STATES.ALIGNING) && (
              <div className="align-overlay">
                <div className="face-guide">
                  <div className="face-oval" />
                  <p className="align-hint">
                    {appState === STATES.IDLE
                      ? "Position your face within the oval"
                      : faceAligned ? "Face detected — starting…" : "Hold still…"}
                  </p>
                </div>
              </div>
            )}

            {/* Recording HUD */}
            {appState === STATES.RECORDING && (
              <div className="recording-hud">
                <div className="rec-badge"><span className="rec-dot" /> REC</div>
                <div className="countdown">{timeLeft}s</div>
              </div>
            )}

            {/* Spinner — only while processing AND radar not yet shown */}
            {appState === STATES.PROCESSING && !showRadar && (
              <div className="processing-overlay">
                <div className="spinner" />
                <p className="processing-step">{processingMsg}</p>
              </div>
            )}
          </div>

          {appState === STATES.RECORDING && (
            <div className="progress-track">
              <div className="progress-fill" style={{ width: `${progress}%` }} />
              <span className="progress-label">{Math.round(progress)}%</span>
            </div>
          )}

          <div className="cta-row">
            {(appState === STATES.IDLE || appState === STATES.ERROR) && (
              <button className="btn-primary" onClick={startSession}>
                {appState === STATES.ERROR ? "Try Again" : "Begin Scan"}
              </button>
            )}
            {appState === STATES.RESULTS && (
              <>
                <button className="btn-secondary" onClick={reset}>New Scan</button>
                <button
                  className="btn-legend"
                  onClick={() => setShowLegend(v => !v)}
                >
                  {showLegend ? "Hide chart guide" : "How to read this chart ↗"}
                </button>
              </>
            )}
            {appState === STATES.ERROR && (
              <p className="error-msg">{errorMsg}</p>
            )}
          </div>

          {/* Radar legend — shown inline below the camera frame */}
          {showLegend && appState === STATES.RESULTS && (
            <RadarLegend vitals={displayVitals} />
          )}
        </section>

        {/* Right panel — Blood Pressure */}
        <section className="vitals-section">
          <h2 className="vitals-heading">Blood Pressure</h2>
          <div className="vitals-grid">
            <VitalCard
              label="Systolic" unit="mmHg"
              value={displayVitals?.sbp_mean != null
                ? Math.round(displayVitals.sbp_mean) : null}
              icon="↑" accent="#00ff88"
              normal={[90, 120]} limits={[70, 180]}
              active={isActive}
            />
            <VitalCard
              label="Diastolic" unit="mmHg"
              value={displayVitals?.dbp_mean != null
                ? Math.round(displayVitals.dbp_mean) : null}
              icon="↓" accent="#a78bfa"
              normal={[60, 80]} limits={[40, 120]}
              active={isActive}
            />
          </div>
          {appState === STATES.RESULTS && results?.sbp_std != null && (
            <div className="bp-detail">
              <span>Variability</span>
              <span>
                ±{Math.round(results.sbp_std)} / ±{Math.round(results.dbp_std)} mmHg
              </span>
            </div>
          )}
        </section>

      </main>

      <footer className="vs-footer">
        <span>VitaSense · Florida Tech Biomedical Engineering</span>
        <span className="footer-note">For research use only — not a medical device</span>
      </footer>
    </div>
  );
}

// ── VitalCard ─────────────────────────────────────────────────────────────────
function VitalCard({ label, unit, value, icon, accent, normal, limits, active }) {
  const inRange  = limits == null || (value != null && value >= limits[0] && value <= limits[1]);
  const display  = inRange ? value : null;
  const isNormal = display != null && display >= normal[0] && display <= normal[1];
  const isHigh   = display != null && display > normal[1];

  return (
    <div
      className={`vital-card ${active && display != null ? "vital-active" : ""}`}
      style={{ "--accent": accent }}
    >
      <div className="vital-icon">{icon}</div>
      <div className="vital-body">
        <span className="vital-label">{label}</span>
        <div className="vital-value-row">
          {active && display != null ? (
            <>
              <span className="vital-number">
                {typeof display === "number"
                  ? (Number.isInteger(display) ? display : display.toFixed(1))
                  : display}
              </span>
              <span className="vital-unit">{unit}</span>
            </>
          ) : (
            <span className="vital-placeholder">—</span>
          )}
        </div>
        {active && display != null && (
          <span className={`vital-status ${
            isNormal ? "status-normal" : isHigh ? "status-high" : "status-low"
          }`}>
            {isNormal ? "Normal" : isHigh ? "Elevated" : "Low"}
          </span>
        )}
      </div>
      <div
        className="vital-ring"
        style={{ borderColor: active && value != null ? accent : "transparent" }}
      />
    </div>
  );
}