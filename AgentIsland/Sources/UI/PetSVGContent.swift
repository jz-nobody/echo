enum PetSVGContent {
    static let resting = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="256" height="256" shape-rendering="crispEdges">
      <style>
        .body { animation: breathe 3s ease-in-out infinite; }
        .z1 { animation: zUp 2.8s ease-out infinite; }
        .z2 { animation: zUp 2.8s ease-out infinite 0.9s; }
        .z3 { animation: zUp 2.8s ease-out infinite 1.8s; }
        @keyframes breathe { 0%, 100% { transform: translateY(0); } 50% { transform: translateY(0.2px); } }
        @keyframes zUp { 0% { opacity: 0; transform: translate(0, 0); } 15% { opacity: 1; } 100% { opacity: 0; transform: translate(0.8px, -2.5px); } }
      </style>
      <rect width="16" height="16" fill="#000000"/>
      <g class="body">
        <rect x="5" y="4" width="1" height="1" fill="#f5f5dc"/><rect x="6" y="4" width="1" height="1" fill="#fffff0"/><rect x="7" y="4" width="1" height="1" fill="#fffff0"/><rect x="8" y="4" width="1" height="1" fill="#fffff0"/><rect x="9" y="4" width="1" height="1" fill="#fffff0"/><rect x="10" y="4" width="1" height="1" fill="#fffff0"/><rect x="11" y="4" width="1" height="1" fill="#f5f5dc"/>
        <rect x="5" y="5" width="1" height="1" fill="#fffff0"/><rect x="6" y="5" width="1" height="1" fill="#ffffff"/><rect x="7" y="5" width="1" height="1" fill="#ffffff"/><rect x="8" y="5" width="1" height="1" fill="#ffffff"/><rect x="9" y="5" width="1" height="1" fill="#ffffff"/><rect x="10" y="5" width="1" height="1" fill="#ffffff"/><rect x="11" y="5" width="1" height="1" fill="#fffff0"/>
        <rect x="5" y="6" width="1" height="1" fill="#fffff0"/><rect x="6" y="6" width="1" height="1" fill="#ffffff"/><rect x="7" y="6" width="1" height="1" fill="#ffffff"/><rect x="8" y="6" width="1" height="1" fill="#ffffff"/><rect x="9" y="6" width="1" height="1" fill="#ffffff"/><rect x="10" y="6" width="1" height="1" fill="#ffffff"/><rect x="11" y="6" width="1" height="1" fill="#fffff0"/>
        <rect x="5" y="7" width="1" height="1" fill="#fffff0"/><rect x="6" y="7" width="1" height="1" fill="#ffffff"/><rect x="7" y="7" width="1" height="1" fill="#ffffff"/><rect x="8" y="7" width="1" height="1" fill="#ffffff"/><rect x="9" y="7" width="1" height="1" fill="#ffffff"/><rect x="10" y="7" width="1" height="1" fill="#ffffff"/><rect x="11" y="7" width="1" height="1" fill="#fffff0"/>
        <rect x="5" y="8" width="1" height="1" fill="#fffff0"/><rect x="6" y="8" width="1" height="1" fill="#ffffff"/><rect x="7" y="8" width="1" height="1" fill="#ffffff"/><rect x="8" y="8" width="1" height="1" fill="#ffffff"/><rect x="9" y="8" width="1" height="1" fill="#ffffff"/><rect x="10" y="8" width="1" height="1" fill="#ffffff"/><rect x="11" y="8" width="1" height="1" fill="#fffff0"/>
        <rect x="5" y="9" width="1" height="1" fill="#f5f5dc"/><rect x="6" y="9" width="1" height="1" fill="#fffff0"/><rect x="7" y="9" width="1" height="1" fill="#fffff0"/><rect x="8" y="9" width="1" height="1" fill="#fffff0"/><rect x="9" y="9" width="1" height="1" fill="#fffff0"/><rect x="10" y="9" width="1" height="1" fill="#fffff0"/><rect x="11" y="9" width="1" height="1" fill="#f5f5dc"/>
        <rect x="7" y="5" width="1" height="1" fill="#9e9e9e"/><rect x="7" y="6" width="1" height="1" fill="#9e9e9e"/><rect x="10" y="5" width="1" height="1" fill="#9e9e9e"/><rect x="10" y="6" width="1" height="1" fill="#9e9e9e"/>
        <rect x="8" y="8" width="1" height="1" fill="#bdbdbd"/>
        <rect x="6" y="10" width="1" height="1" fill="#e0e0e0"/><rect x="10" y="10" width="1" height="1" fill="#e0e0e0"/>
        <rect x="12" y="6" width="1" height="1" fill="#424242"/><rect x="12" y="7" width="1" height="1" fill="#424242"/><rect x="13" y="7" width="1" height="1" fill="#616161"/>
      </g>
      <g class="z1"><rect x="11" y="3" width="1" height="1" fill="#c5cae9"/><rect x="12" y="2" width="1" height="1" fill="#c5cae9"/><rect x="11" y="2" width="1" height="1" fill="#c5cae9"/></g>
      <g class="z2"><rect x="12" y="1" width="1" height="1" fill="#9fa8da"/><rect x="13" y="1" width="1" height="1" fill="#9fa8da"/></g>
      <g class="z3"><rect x="13" y="0" width="1" height="1" fill="#7986cb"/></g>
    </svg>
    """

    static let working = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="256" height="256" shape-rendering="crispEdges">
      <style>
        .body { animation: bounce 0.6s ease-in-out infinite; }
        .legL { animation: stepL 0.6s ease-in-out infinite; }
        .legR { animation: stepR 0.6s ease-in-out infinite; }
        .cord { animation: swing 0.8s ease-in-out infinite alternate; }
        @keyframes bounce { 0%, 100% { transform: translateY(0); } 50% { transform: translateY(-0.8px); } }
        @keyframes stepL { 0%, 100% { transform: translateX(0) translateY(0); } 50% { transform: translateX(-0.3px) translateY(0.3px); } }
        @keyframes stepR { 0%, 100% { transform: translateX(0) translateY(0); } 50% { transform: translateX(0.3px) translateY(0.3px); } }
        @keyframes swing { 0% { transform: rotate(-5deg); } 100% { transform: rotate(5deg); } }
      </style>
      <rect width="16" height="16" fill="#000000"/>
      <g class="body">
        <rect x="5" y="3" width="1" height="1" fill="#f5f5dc"/><rect x="6" y="3" width="1" height="1" fill="#fffff0"/><rect x="7" y="3" width="1" height="1" fill="#fffff0"/><rect x="8" y="3" width="1" height="1" fill="#fffff0"/><rect x="9" y="3" width="1" height="1" fill="#fffff0"/><rect x="10" y="3" width="1" height="1" fill="#fffff0"/><rect x="11" y="3" width="1" height="1" fill="#f5f5dc"/>
        <rect x="5" y="4" width="1" height="1" fill="#fffff0"/><rect x="6" y="4" width="1" height="1" fill="#ffffff"/><rect x="7" y="4" width="1" height="1" fill="#ffffff"/><rect x="8" y="4" width="1" height="1" fill="#ffffff"/><rect x="9" y="4" width="1" height="1" fill="#ffffff"/><rect x="10" y="4" width="1" height="1" fill="#ffffff"/><rect x="11" y="4" width="1" height="1" fill="#fffff0"/>
        <rect x="5" y="5" width="1" height="1" fill="#fffff0"/><rect x="6" y="5" width="1" height="1" fill="#ffffff"/><rect x="7" y="5" width="1" height="1" fill="#ffffff"/><rect x="8" y="5" width="1" height="1" fill="#ffffff"/><rect x="9" y="5" width="1" height="1" fill="#ffffff"/><rect x="10" y="5" width="1" height="1" fill="#ffffff"/><rect x="11" y="5" width="1" height="1" fill="#fffff0"/>
        <rect x="5" y="6" width="1" height="1" fill="#fffff0"/><rect x="6" y="6" width="1" height="1" fill="#ffffff"/><rect x="7" y="6" width="1" height="1" fill="#ffffff"/><rect x="8" y="6" width="1" height="1" fill="#ffffff"/><rect x="9" y="6" width="1" height="1" fill="#ffffff"/><rect x="10" y="6" width="1" height="1" fill="#ffffff"/><rect x="11" y="6" width="1" height="1" fill="#fffff0"/>
        <rect x="5" y="7" width="1" height="1" fill="#fffff0"/><rect x="6" y="7" width="1" height="1" fill="#ffffff"/><rect x="7" y="7" width="1" height="1" fill="#ffffff"/><rect x="8" y="7" width="1" height="1" fill="#ffffff"/><rect x="9" y="7" width="1" height="1" fill="#ffffff"/><rect x="10" y="7" width="1" height="1" fill="#ffffff"/><rect x="11" y="7" width="1" height="1" fill="#fffff0"/>
        <rect x="5" y="8" width="1" height="1" fill="#f5f5dc"/><rect x="6" y="8" width="1" height="1" fill="#fffff0"/><rect x="7" y="8" width="1" height="1" fill="#fffff0"/><rect x="8" y="8" width="1" height="1" fill="#fffff0"/><rect x="9" y="8" width="1" height="1" fill="#fffff0"/><rect x="10" y="8" width="1" height="1" fill="#fffff0"/><rect x="11" y="8" width="1" height="1" fill="#f5f5dc"/>
        <rect x="7" y="4" width="1" height="1" fill="#212121"/><rect x="7" y="5" width="1" height="1" fill="#212121"/><rect x="10" y="4" width="1" height="1" fill="#212121"/><rect x="10" y="5" width="1" height="1" fill="#212121"/>
        <rect x="8" y="7" width="1" height="1" fill="#212121"/><rect x="9" y="7" width="1" height="1" fill="#212121"/>
      </g>
      <g class="legL"><rect x="6" y="9" width="1" height="1" fill="#f5f5dc"/><rect x="6" y="10" width="1" height="1" fill="#e0e0e0"/></g>
      <g class="legR"><rect x="10" y="9" width="1" height="1" fill="#f5f5dc"/><rect x="10" y="10" width="1" height="1" fill="#e0e0e0"/></g>
      <g class="cord"><rect x="12" y="5" width="1" height="1" fill="#424242"/><rect x="13" y="6" width="1" height="1" fill="#424242"/><rect x="13" y="7" width="1" height="1" fill="#424242"/><rect x="12" y="8" width="1" height="1" fill="#616161"/></g>
    </svg>
    """

    static let compacting = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="256" height="256" shape-rendering="crispEdges">
      <style>
        .body { animation: tilt 1.4s ease-in-out infinite; transform-origin: 8px 5px; }
        .armL { animation: kneadL 1.4s ease-in-out infinite; }
        .armR { animation: kneadR 1.4s ease-in-out infinite; }
        .paper { animation: roll 1.4s ease-in-out infinite; transform-origin: 8px 12px; }
        @keyframes tilt { 0%, 100% { transform: rotate(0deg); } 25% { transform: rotate(-4deg); } 75% { transform: rotate(4deg); } }
        @keyframes kneadL { 0%, 100% { transform: translate(0, 0); } 25% { transform: translate(0.3px, 0.2px); } 75% { transform: translate(-0.3px, 0); } }
        @keyframes kneadR { 0%, 100% { transform: translate(0, 0); } 25% { transform: translate(-0.3px, 0); } 75% { transform: translate(0.3px, 0.2px); } }
        @keyframes roll { 0%, 100% { transform: translateX(0) rotate(0deg); } 25% { transform: translateX(-0.5px) rotate(-8deg); } 75% { transform: translateX(0.5px) rotate(8deg); } }
      </style>
      <rect width="16" height="16" fill="#000000"/>
      <g class="body">
        <rect x="5" y="2" width="1" height="1" fill="#f5f5dc"/><rect x="6" y="2" width="1" height="1" fill="#fffff0"/><rect x="7" y="2" width="1" height="1" fill="#fffff0"/><rect x="8" y="2" width="1" height="1" fill="#fffff0"/><rect x="9" y="2" width="1" height="1" fill="#fffff0"/><rect x="10" y="2" width="1" height="1" fill="#fffff0"/><rect x="11" y="2" width="1" height="1" fill="#f5f5dc"/>
        <rect x="5" y="3" width="1" height="1" fill="#fffff0"/><rect x="6" y="3" width="1" height="1" fill="#ffffff"/><rect x="7" y="3" width="1" height="1" fill="#ffffff"/><rect x="8" y="3" width="1" height="1" fill="#ffffff"/><rect x="9" y="3" width="1" height="1" fill="#ffffff"/><rect x="10" y="3" width="1" height="1" fill="#ffffff"/><rect x="11" y="3" width="1" height="1" fill="#fffff0"/>
        <rect x="5" y="4" width="1" height="1" fill="#fffff0"/><rect x="6" y="4" width="1" height="1" fill="#ffffff"/><rect x="7" y="4" width="1" height="1" fill="#ffffff"/><rect x="8" y="4" width="1" height="1" fill="#ffffff"/><rect x="9" y="4" width="1" height="1" fill="#ffffff"/><rect x="10" y="4" width="1" height="1" fill="#ffffff"/><rect x="11" y="4" width="1" height="1" fill="#fffff0"/>
        <rect x="5" y="5" width="1" height="1" fill="#fffff0"/><rect x="6" y="5" width="1" height="1" fill="#ffffff"/><rect x="7" y="5" width="1" height="1" fill="#ffffff"/><rect x="8" y="5" width="1" height="1" fill="#ffffff"/><rect x="9" y="5" width="1" height="1" fill="#ffffff"/><rect x="10" y="5" width="1" height="1" fill="#ffffff"/><rect x="11" y="5" width="1" height="1" fill="#fffff0"/>
        <rect x="5" y="6" width="1" height="1" fill="#fffff0"/><rect x="6" y="6" width="1" height="1" fill="#ffffff"/><rect x="7" y="6" width="1" height="1" fill="#ffffff"/><rect x="8" y="6" width="1" height="1" fill="#ffffff"/><rect x="9" y="6" width="1" height="1" fill="#ffffff"/><rect x="10" y="6" width="1" height="1" fill="#ffffff"/><rect x="11" y="6" width="1" height="1" fill="#fffff0"/>
        <rect x="5" y="7" width="1" height="1" fill="#f5f5dc"/><rect x="6" y="7" width="1" height="1" fill="#fffff0"/><rect x="7" y="7" width="1" height="1" fill="#fffff0"/><rect x="8" y="7" width="1" height="1" fill="#fffff0"/><rect x="9" y="7" width="1" height="1" fill="#fffff0"/><rect x="10" y="7" width="1" height="1" fill="#fffff0"/><rect x="11" y="7" width="1" height="1" fill="#f5f5dc"/>
        <rect x="7" y="4" width="1" height="1" fill="#424242"/><rect x="7" y="5" width="1" height="1" fill="#212121"/><rect x="10" y="4" width="1" height="1" fill="#424242"/><rect x="10" y="5" width="1" height="1" fill="#212121"/>
        <rect x="8" y="6" width="1" height="1" fill="#9e9e9e"/><rect x="9" y="6" width="1" height="1" fill="#9e9e9e"/>
        <rect x="12" y="4" width="1" height="1" fill="#424242"/><rect x="12" y="5" width="1" height="1" fill="#424242"/><rect x="13" y="6" width="1" height="1" fill="#616161"/>
      </g>
      <g class="armL"><rect x="5" y="8" width="1" height="1" fill="#e0e0e0"/><rect x="5" y="9" width="1" height="1" fill="#e0e0e0"/><rect x="6" y="10" width="1" height="1" fill="#e0e0e0"/><rect x="7" y="11" width="1" height="1" fill="#d4d4d4"/></g>
      <g class="armR"><rect x="11" y="8" width="1" height="1" fill="#e0e0e0"/><rect x="11" y="9" width="1" height="1" fill="#e0e0e0"/><rect x="10" y="10" width="1" height="1" fill="#e0e0e0"/><rect x="9" y="11" width="1" height="1" fill="#d4d4d4"/></g>
      <g class="paper"><rect x="7" y="12" width="1" height="1" fill="#bdbdbd"/><rect x="8" y="11" width="1" height="1" fill="#e8e8e8"/><rect x="8" y="12" width="1" height="1" fill="#f5f5f5"/><rect x="9" y="12" width="1" height="1" fill="#e0e0e0"/><rect x="8" y="13" width="1" height="1" fill="#d4d4d4"/><rect x="9" y="13" width="1" height="1" fill="#bdbdbd"/></g>
    </svg>
    """

    static let questioning = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="256" height="256" shape-rendering="crispEdges">
      <style>
        .qmark { animation: fadeInOut 1.8s ease-in-out infinite; }
        .body { animation: wobble 2.5s ease-in-out infinite; }
        .eyeL { animation: lookLeft 3s ease-in-out infinite; }
        .eyeR { animation: lookLeft 3s ease-in-out infinite; }
        @keyframes fadeInOut { 0% { opacity: 0; transform: translateY(0.5px); } 30% { opacity: 1; transform: translateY(0); } 70% { opacity: 1; transform: translateY(0); } 100% { opacity: 0; transform: translateY(-0.5px); } }
        @keyframes wobble { 0%, 100% { transform: rotate(0); } 20% { transform: rotate(-3deg); } 40% { transform: rotate(3deg); } 60% { transform: rotate(-1deg); } 80% { transform: rotate(1deg); } }
        @keyframes lookLeft { 0%, 40% { transform: translateX(0); } 50% { transform: translateX(-0.3px); } 60%, 100% { transform: translateX(0); } }
      </style>
      <rect width="16" height="16" fill="#000000"/>
      <g class="body">
        <rect x="5" y="3" width="1" height="1" fill="#f5f5dc"/><rect x="6" y="3" width="1" height="1" fill="#fffff0"/><rect x="7" y="3" width="1" height="1" fill="#fffff0"/><rect x="8" y="3" width="1" height="1" fill="#fffff0"/><rect x="9" y="3" width="1" height="1" fill="#fffff0"/><rect x="10" y="3" width="1" height="1" fill="#fffff0"/><rect x="11" y="3" width="1" height="1" fill="#f5f5dc"/>
        <rect x="5" y="4" width="1" height="1" fill="#fffff0"/><rect x="6" y="4" width="1" height="1" fill="#ffffff"/><rect x="7" y="4" width="1" height="1" fill="#ffffff"/><rect x="8" y="4" width="1" height="1" fill="#ffffff"/><rect x="9" y="4" width="1" height="1" fill="#ffffff"/><rect x="10" y="4" width="1" height="1" fill="#ffffff"/><rect x="11" y="4" width="1" height="1" fill="#fffff0"/>
        <rect x="5" y="5" width="1" height="1" fill="#fffff0"/><rect x="6" y="5" width="1" height="1" fill="#ffffff"/><rect x="7" y="5" width="1" height="1" fill="#ffffff"/><rect x="8" y="5" width="1" height="1" fill="#ffffff"/><rect x="9" y="5" width="1" height="1" fill="#ffffff"/><rect x="10" y="5" width="1" height="1" fill="#ffffff"/><rect x="11" y="5" width="1" height="1" fill="#fffff0"/>
        <rect x="5" y="6" width="1" height="1" fill="#fffff0"/><rect x="6" y="6" width="1" height="1" fill="#ffffff"/><rect x="7" y="6" width="1" height="1" fill="#ffffff"/><rect x="8" y="6" width="1" height="1" fill="#ffffff"/><rect x="9" y="6" width="1" height="1" fill="#ffffff"/><rect x="10" y="6" width="1" height="1" fill="#ffffff"/><rect x="11" y="6" width="1" height="1" fill="#fffff0"/>
        <rect x="5" y="7" width="1" height="1" fill="#fffff0"/><rect x="6" y="7" width="1" height="1" fill="#ffffff"/><rect x="7" y="7" width="1" height="1" fill="#ffffff"/><rect x="8" y="7" width="1" height="1" fill="#ffffff"/><rect x="9" y="7" width="1" height="1" fill="#ffffff"/><rect x="10" y="7" width="1" height="1" fill="#ffffff"/><rect x="11" y="7" width="1" height="1" fill="#fffff0"/>
        <rect x="5" y="8" width="1" height="1" fill="#f5f5dc"/><rect x="6" y="8" width="1" height="1" fill="#fffff0"/><rect x="7" y="8" width="1" height="1" fill="#fffff0"/><rect x="8" y="8" width="1" height="1" fill="#fffff0"/><rect x="9" y="8" width="1" height="1" fill="#fffff0"/><rect x="10" y="8" width="1" height="1" fill="#fffff0"/><rect x="11" y="8" width="1" height="1" fill="#f5f5dc"/>
        <g class="eyeL"><rect x="6" y="4" width="1" height="1" fill="#212121"/><rect x="6" y="5" width="1" height="1" fill="#212121"/></g>
        <g class="eyeR"><rect x="9" y="4" width="1" height="1" fill="#212121"/><rect x="9" y="5" width="1" height="1" fill="#212121"/></g>
        <rect x="7" y="7" width="1" height="1" fill="#9e9e9e"/><rect x="8" y="7" width="1" height="1" fill="#616161"/><rect x="9" y="7" width="1" height="1" fill="#9e9e9e"/>
        <rect x="6" y="9" width="1" height="1" fill="#f5f5dc"/><rect x="6" y="10" width="1" height="1" fill="#e0e0e0"/><rect x="10" y="9" width="1" height="1" fill="#f5f5dc"/><rect x="10" y="10" width="1" height="1" fill="#e0e0e0"/>
        <rect x="12" y="5" width="1" height="1" fill="#424242"/><rect x="13" y="6" width="1" height="1" fill="#424242"/><rect x="13" y="7" width="1" height="1" fill="#424242"/>
      </g>
      <g class="qmark"><rect x="2" y="2" width="1" height="1" fill="#ff1744"/><rect x="3" y="2" width="1" height="1" fill="#ff1744"/><rect x="4" y="2" width="1" height="1" fill="#ff1744"/><rect x="4" y="3" width="1" height="1" fill="#ff1744"/><rect x="3" y="4" width="1" height="1" fill="#ff5252"/><rect x="3" y="5" width="1" height="1" fill="#ff1744"/><rect x="3" y="7" width="1" height="1" fill="#ff1744"/></g>
    </svg>
    """

    static let socketFace = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="256" height="256" shape-rendering="crispEdges">
      <rect width="16" height="16" fill="#000000"/>
      <rect x="4" y="3" width="1" height="1" fill="#f5f5dc"/><rect x="5" y="3" width="1" height="1" fill="#fffff0"/><rect x="6" y="3" width="1" height="1" fill="#fffff0"/><rect x="7" y="3" width="1" height="1" fill="#fffff0"/><rect x="8" y="3" width="1" height="1" fill="#fffff0"/><rect x="9" y="3" width="1" height="1" fill="#fffff0"/><rect x="10" y="3" width="1" height="1" fill="#fffff0"/><rect x="11" y="3" width="1" height="1" fill="#f5f5dc"/>
      <rect x="4" y="4" width="1" height="1" fill="#fffff0"/><rect x="5" y="4" width="1" height="1" fill="#ffffff"/><rect x="6" y="4" width="1" height="1" fill="#ffffff"/><rect x="7" y="4" width="1" height="1" fill="#ffffff"/><rect x="8" y="4" width="1" height="1" fill="#ffffff"/><rect x="9" y="4" width="1" height="1" fill="#ffffff"/><rect x="10" y="4" width="1" height="1" fill="#ffffff"/><rect x="11" y="4" width="1" height="1" fill="#fffff0"/>
      <rect x="4" y="5" width="1" height="1" fill="#fffff0"/><rect x="5" y="5" width="1" height="1" fill="#ffffff"/><rect x="6" y="5" width="1" height="1" fill="#ffffff"/><rect x="7" y="5" width="1" height="1" fill="#ffffff"/><rect x="8" y="5" width="1" height="1" fill="#ffffff"/><rect x="9" y="5" width="1" height="1" fill="#ffffff"/><rect x="10" y="5" width="1" height="1" fill="#ffffff"/><rect x="11" y="5" width="1" height="1" fill="#fffff0"/>
      <rect x="4" y="6" width="1" height="1" fill="#fffff0"/><rect x="5" y="6" width="1" height="1" fill="#ffffff"/><rect x="6" y="6" width="1" height="1" fill="#ffffff"/><rect x="7" y="6" width="1" height="1" fill="#ffffff"/><rect x="8" y="6" width="1" height="1" fill="#ffffff"/><rect x="9" y="6" width="1" height="1" fill="#ffffff"/><rect x="10" y="6" width="1" height="1" fill="#ffffff"/><rect x="11" y="6" width="1" height="1" fill="#fffff0"/>
      <rect x="4" y="7" width="1" height="1" fill="#fffff0"/><rect x="5" y="7" width="1" height="1" fill="#ffffff"/><rect x="6" y="7" width="1" height="1" fill="#ffffff"/><rect x="7" y="7" width="1" height="1" fill="#ffffff"/><rect x="8" y="7" width="1" height="1" fill="#ffffff"/><rect x="9" y="7" width="1" height="1" fill="#ffffff"/><rect x="10" y="7" width="1" height="1" fill="#ffffff"/><rect x="11" y="7" width="1" height="1" fill="#fffff0"/>
      <rect x="4" y="8" width="1" height="1" fill="#f5f5dc"/><rect x="5" y="8" width="1" height="1" fill="#fffff0"/><rect x="6" y="8" width="1" height="1" fill="#fffff0"/><rect x="7" y="8" width="1" height="1" fill="#fffff0"/><rect x="8" y="8" width="1" height="1" fill="#fffff0"/><rect x="9" y="8" width="1" height="1" fill="#fffff0"/><rect x="10" y="8" width="1" height="1" fill="#fffff0"/><rect x="11" y="8" width="1" height="1" fill="#f5f5dc"/>
      <rect x="6" y="4" width="1" height="1" fill="#212121"/><rect x="6" y="5" width="1" height="1" fill="#212121"/><rect x="9" y="4" width="1" height="1" fill="#212121"/><rect x="9" y="5" width="1" height="1" fill="#212121"/>
      <rect x="7" y="7" width="1" height="1" fill="#212121"/><rect x="8" y="7" width="1" height="1" fill="#212121"/>
      <rect x="5" y="9" width="1" height="1" fill="#f5f5dc"/><rect x="5" y="10" width="1" height="1" fill="#e0e0e0"/><rect x="10" y="9" width="1" height="1" fill="#f5f5dc"/><rect x="10" y="10" width="1" height="1" fill="#e0e0e0"/>
      <rect x="5" y="3" width="1" height="1" fill="#ffeb3b"/><rect x="10" y="3" width="1" height="1" fill="#ffeb3b"/><rect x="6" y="5" width="1" height="1" fill="#42a5f5"/><rect x="9" y="5" width="1" height="1" fill="#42a5f5"/>
      <rect x="12" y="5" width="1" height="1" fill="#424242"/><rect x="13" y="6" width="1" height="1" fill="#424242"/><rect x="13" y="7" width="1" height="1" fill="#424242"/><rect x="12" y="8" width="1" height="1" fill="#424242"/><rect x="12" y="9" width="1" height="1" fill="#616161"/>
    </svg>
    """

    static func svgContent(for name: String) -> String {
        switch name {
        case "resting": resting
        case "working": working
        case "compacting": compacting
        case "questioning": questioning
        case "socket-face": socketFace
        default: socketFace
        }
    }
}
