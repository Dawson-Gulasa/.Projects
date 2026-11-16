# Robotics and Automated Inspection Research

**University of Georgia · Summer 2025 · Dr. Hongyue Sun's research group**

**Robot vision · 3D perception · Manipulator integration · Automated inspection · Python**

## Research overview

Research supporting a robotic inspection workflow that combines **object detection, depth sensing, 3D pose estimation, and manipulator control**. Work included integrating robotic arms such as UR5e/DOBOT, depth and camera processing, object pose/orientation computation, conveyor or scanning workflows, and structured inspection/report generation.

The most useful resource is the original [Research Memo (PDF)](Research_Memo.pdf), which documents the research problem, architecture, experiments, code references, diagrams, and demonstration videos.

## Engineering workflow

```text
RGB + depth / scanner input
              ↓
Object recognition and geometry extraction
              ↓
Point-cloud / PCA-based oriented bounding box
              ↓
6D pose estimate and target alignment
              ↓
Robot manipulation / scanner data capture
              ↓
Inspection output + generated report
```

This is a **research documentation portfolio entry**, not a public source-code release. The original laboratory code and data are not all committed here; the memo provides available context and demonstrations.

## Skills demonstrated

- Python integration across depth processing, vision, robot communications, and automated reporting
- Geometric analysis and object alignment using PCA/oriented bounding boxes and pose frames
- Hardware/software integration with robotic manipulator and scanning instrumentation
- Iterative experiments, documentation, defect/quality-inspection workflow, reproducible reporting

## Research outputs and access

- **[Research Memo](Research_Memo.pdf)** — methods, diagrams, development record and video references.
- **[AutoInspector — NSF Public Access Repository entry](https://par.nsf.gov/biblio/10716809-autoinspector-autonomous-robotic-scanning-framework-quality-inspection)** — user-supplied research record. The associated publication is reported as not publicly accessible until **2027**; link here is a bibliographic pointer, **not a claim that the full paper is currently open access**.

## Credit

The work was conducted in **Dr. Hongyue Sun's University of Georgia research laboratory** and involved academic collaborators and mentors. Dawson contributed to perception/robot integration and inspection workflow engineering. The entire lab framework and any later publication are **collaborative research outputs**, not individual work.

For specifics, research data, and demonstration links, see the [full memo](Research_Memo.pdf). Third-party figures and unpublished artifacts should not be redistributed outside their documented permissions.
