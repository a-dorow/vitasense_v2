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

export default function VitaSense() {
  const videoRef        = useRef(null);
  const mediaRecorderRef = useRef(null);
  const chunksRef       = useRef([]);
  const streamRef       = useRef(null);
  const alignTimerRef   = useRef(null);
  const esRef           = useRef(null);  // EventSource ref

  const [appState,     setAppState]     = useState(STATES.IDLE);
  const [progress,     setProgress]     = useState(0);
  const [timeLeft,     setTimeLeft]     = useState(RECORD_SECONDS);
  const [processingMsg, setProcessingMsg] = useState("Starting pipeline...");
  const [results,      setResults]      = useState(null);
  const [errorMsg,     setErrorMsg]     = useState("");
  const [faceAligned,  setFaceAligned]  = useState(false);

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
      esRef.current?.close();
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

    // Step 1: Upload video, get job_id back immediately
    let job_id;
    try {
      const res = await fetch(`${API_BASE}/analyze`, {
        method: "POST",
        body: formData,
      });
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

    // Step 2: Connect to SSE via fetch + ReadableStream
    // More reliable than EventSource which misfires onerror on keepalives
    setProcessingMsg("Starting MATLAB pipeline...");

    const abortCtrl = new AbortController();
    esRef.current = abortCtrl;

    try {
      const sseRes = await fetch(`${API_BASE}/progress/${job_id}`, {
        signal: abortCtrl.signal,
      });

      if (!sseRes.ok) {
        throw new Error(`SSE connection failed: ${sseRes.status}`);
      }

      const reader  = sseRes.body.getReader();
      const decoder = new TextDecoder();
      let   buffer  = "";

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });

        // SSE messages separated by \n\n
        const parts = buffer.split("\n\n");
        buffer = parts.pop();

        for (const part of parts) {
          if (part.startsWith(":")) continue; // keepalive comment

          const dataLine = part.split("\n").find(l => l.startsWith("data:"));
          if (!dataLine) continue;

          try {
            const msg = JSON.parse(dataLine.slice(5).trim());

            if (msg.type === "progress") {
              setProcessingMsg(msg.message);
            } else if (msg.type === "result") {
              abortCtrl.abort();
              setResults(msg.data);
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

  const reset = () => {
    esRef.current?.abort?.();  // AbortController
    esRef.current?.close?.();  // fallback if EventSource
    setAppState(STATES.IDLE);
    setResults(null);
    setProgress(0);
    setTimeLeft(RECORD_SECONDS);
    setFaceAligned(false);
    setErrorMsg("");
    setProcessingMsg("Starting pipeline...");
  };

  const borderClass =
    appState === STATES.RECORDING ? "border-recording"
    : faceAligned                 ? "border-aligned"
    : appState === STATES.ALIGNING ? "border-aligning"
    : "border-idle";

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
            <VitalCard label="Heart Rate" unit="bpm" value={results?.hr_bpm}    icon="♥" accent="#ff6b00" normal={[60,100]} limits={[40,200]} active={appState===STATES.RESULTS} />
            <VitalCard label="SpO₂"       unit="%"   value={results?.spo2_pct}  icon="◉" accent="#00d4ff" normal={[95,100]} limits={[80,100]} active={appState===STATES.RESULTS} />
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

        {/* Center — Camera */}
        <section className="camera-section">
          <div className={`camera-frame ${borderClass}`}>
            <div className="corner tl"/><div className="corner tr"/>
            <div className="corner bl"/><div className="corner br"/>

            <video ref={videoRef} autoPlay playsInline muted className="camera-feed" />

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

            {appState === STATES.RECORDING && (
              <div className="recording-hud">
                <div className="rec-badge"><span className="rec-dot" /> REC</div>
                <div className="countdown">{timeLeft}s</div>
              </div>
            )}

            {appState === STATES.PROCESSING && (
              <div className="processing-overlay">
                <div className="spinner" />
                <p className="processing-step">{processingMsg}</p>
              </div>
            )}

            {appState === STATES.RESULTS && (
              <div className="results-stamp">
                <span className="stamp-icon">✓</span>
                <span>Analysis Complete</span>
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
              <button className="btn-secondary" onClick={reset}>New Scan</button>
            )}
            {appState === STATES.ERROR && (
              <p className="error-msg">{errorMsg}</p>
            )}
          </div>
        </section>

        {/* Right panel — Blood Pressure */}
        <section className="vitals-section">
          <h2 className="vitals-heading">Blood Pressure</h2>
          <div className="vitals-grid">
            <VitalCard label="Systolic"  unit="mmHg" value={results?.sbp_mean != null ? Math.round(results.sbp_mean) : null} icon="↑" accent="#00ff88" normal={[90,120]} limits={[70,180]} active={appState===STATES.RESULTS} />
            <VitalCard label="Diastolic" unit="mmHg" value={results?.dbp_mean != null ? Math.round(results.dbp_mean) : null} icon="↓" accent="#a78bfa" normal={[60,80]}  limits={[40,120]} active={appState===STATES.RESULTS} />
          </div>
          {appState === STATES.RESULTS && results?.sbp_std != null && (
            <div className="bp-detail">
              <span>Variability</span>
              <span>±{Math.round(results.sbp_std)} / ±{Math.round(results.dbp_std)} mmHg</span>
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

function VitalCard({ label, unit, value, icon, accent, normal, limits, active }) {
  // Outside physiological limits = show as invalid (—)
  const inRange  = limits == null || (value != null && value >= limits[0] && value <= limits[1]);
  const display  = inRange ? value : null;
  const isNormal = display != null && display >= normal[0] && display <= normal[1];
  const isHigh   = display != null && display > normal[1];

  return (
    <div className={`vital-card ${active ? "vital-active" : ""}`} style={{ "--accent": accent }}>
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
          <span className={`vital-status ${isNormal ? "status-normal" : isHigh ? "status-high" : "status-low"}`}>
            {isNormal ? "Normal" : isHigh ? "Elevated" : "Low"}
          </span>
        )}
      </div>
      <div className="vital-ring" style={{ borderColor: active && value != null ? accent : "transparent" }} />
    </div>
  );
}