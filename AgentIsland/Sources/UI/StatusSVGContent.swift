import Foundation

enum StatusSVGContent {
    static func svgContent(for name: String) -> String {
        switch name {
        case "idle": idleSVG
        case "running": runningSVG
        case "compacting": compactingSVG
        case "asking": askingSVG
        default: idleSVG
        }
    }

    private static let idleSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="100%" height="100%">
      <style>
        .cursor { animation: blink 1s step-end infinite; }
        @keyframes blink {
          0%, 50% { opacity: 1; }
          50.1%, 100% { opacity: 0; }
        }
      </style>
      <g class="cursor">
        <rect x="6" y="3" width="4" height="10" rx="1" fill="#4caf50"/>
      </g>
    </svg>
    """

    private static let runningSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="100%" height="100%">
      <style>
        .spinner { animation: spin 1s linear infinite; transform-origin: 8px 8px; }
        @keyframes spin {
          0% { transform: rotate(0deg); }
          100% { transform: rotate(360deg); }
        }
      </style>
      <g class="spinner">
        <circle cx="8" cy="2.5" r="1.2" fill="#1565c0"/>
        <circle cx="11.9" cy="4.1" r="1.1" fill="#1976d2"/>
        <circle cx="13.5" cy="8" r="1" fill="#2196f3"/>
        <circle cx="11.9" cy="11.9" r="0.9" fill="#42a5f5"/>
        <circle cx="8" cy="13.5" r="0.8" fill="#64b5f6"/>
        <circle cx="4.1" cy="11.9" r="0.7" fill="#90caf9"/>
        <circle cx="2.5" cy="8" r="0.6" fill="#bbdefb"/>
        <circle cx="4.1" cy="4.1" r="0.5" fill="#e3f2fd"/>
      </g>
    </svg>
    """

    private static let compactingSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="100%" height="100%">
      <style>
        .particle { animation: suck 1.2s ease-in infinite; transform-origin: 8px 8px; }
        .p1 { animation-delay: 0s; }
        .p2 { animation-delay: 0.2s; }
        .p3 { animation-delay: 0.4s; }
        .p4 { animation-delay: 0.6s; }
        .p5 { animation-delay: 0.8s; }
        .p6 { animation-delay: 1s; }
        .hole { animation: throb 1.2s ease-in-out infinite; transform-origin: 8px 8px; }
        @keyframes suck {
          0% { transform: scale(1); opacity: 1; }
          100% { transform: scale(0); opacity: 0; }
        }
        @keyframes throb {
          0%, 100% { transform: scale(1); }
          50% { transform: scale(1.3); }
        }
      </style>
      <g class="hole">
        <circle cx="8" cy="8" r="1.5" fill="#4a148c"/>
      </g>
      <g class="particle p1"><circle cx="2.5" cy="2.5" r="1.2" fill="#ce93d8"/></g>
      <g class="particle p2"><circle cx="13.5" cy="3" r="1" fill="#e1bee7"/></g>
      <g class="particle p3"><circle cx="2.5" cy="13" r="1.1" fill="#9c27b0"/></g>
      <g class="particle p4"><circle cx="13.5" cy="13" r="1" fill="#ce93d8"/></g>
      <g class="particle p5"><circle cx="1.5" cy="8" r="0.9" fill="#e1bee7"/></g>
      <g class="particle p6"><circle cx="14.5" cy="8" r="1.1" fill="#9c27b0"/></g>
    </svg>
    """

    private static let askingSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="100%" height="100%">
      <style>
        .qmark { animation: blink 1.2s ease-in-out infinite; }
        @keyframes blink {
          0%, 100% { opacity: 1; transform: translateY(0); }
          50% { opacity: 0.4; transform: translateY(-0.5px); }
        }
      </style>
      <g class="qmark">
        <path d="M6 4.5 C6 2.8 7.2 2 8.2 2 C9.5 2 10.8 2.8 10.8 4.2 C10.8 5.3 10 5.8 9.2 6.4 C8.6 6.9 8.3 7.3 8.3 8" stroke="#ffc107" stroke-width="1.5" stroke-linecap="round" fill="none"/>
        <circle cx="8.3" cy="10.5" r="1" fill="#ffc107"/>
      </g>
    </svg>
    """
}
