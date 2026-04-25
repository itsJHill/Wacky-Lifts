import UIKit

protocol WorkoutTimerViewControllerDelegate: AnyObject {
    func workoutTimer(_ controller: WorkoutTimerViewController, didCompleteExercise exercise: WorkoutTemplate.Exercise, in workout: WorkoutTemplate)
    func workoutTimerDidComplete(_ controller: WorkoutTimerViewController, workout: WorkoutTemplate)
    func workoutTimerDidCancel(_ controller: WorkoutTimerViewController)
}

final class WorkoutTimerViewController: UIViewController {

    // MARK: - Types

    struct TimerStep {
        let exerciseIndex: Int
        let exercise: WorkoutTemplate.Exercise
        let durationSeconds: TimeInterval
        let setNumber: Int   // 1-based, 0 if no sets
        let totalSets: Int   // 0 if no sets
    }

    // MARK: - Properties

    weak var delegate: WorkoutTimerViewControllerDelegate?

    private let workout: WorkoutTemplate
    private let selectedDate: Date
    private let singleExercise: WorkoutTemplate.Exercise?
    private var steps: [TimerStep] = []
    private var currentStepIndex = 0
    private var elapsedTime: TimeInterval = 0
    private var timer: Timer?
    private var isRunning = false
    private var completedExerciseIndices: Set<Int> = []

    // MARK: - UI Components

    private let workoutIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.tintColor = .systemBlue
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let workoutNameLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let closeButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        button.setImage(UIImage(systemName: "xmark", withConfiguration: config), for: .normal)
        button.tintColor = .secondaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let stepCounterLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let exerciseNameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 28, weight: .bold)
        label.textColor = .label
        label.textAlignment = .center
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let setLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let ringContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 48, weight: .light)
        label.textColor = .label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let prevButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        button.setImage(UIImage(systemName: "backward.end.fill", withConfiguration: config), for: .normal)
        button.tintColor = .label
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let playPauseButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 44, weight: .medium)
        button.setImage(UIImage(systemName: "play.circle.fill", withConfiguration: config), for: .normal)
        button.tintColor = .systemBlue
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let nextButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        button.setImage(UIImage(systemName: "forward.end.fill", withConfiguration: config), for: .normal)
        button.tintColor = .label
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private var trackLayer: CAShapeLayer!
    private var progressLayer: CAShapeLayer!

    private let ringSize: CGFloat = 240
    private let ringLineWidth: CGFloat = 12

    // MARK: - Init

    init(workout: WorkoutTemplate, selectedDate: Date) {
        self.workout = workout
        self.selectedDate = selectedDate
        self.singleExercise = nil
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    init(exercise: WorkoutTemplate.Exercise, workout: WorkoutTemplate, selectedDate: Date) {
        self.workout = workout
        self.selectedDate = selectedDate
        self.singleExercise = exercise
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        buildSteps()
        setupUI()
        setupActions()
        if steps.count <= 1 {
            prevButton.isHidden = true
            nextButton.isHidden = true
        }
        updateDisplay()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
    }

    deinit {
        timer?.invalidate()
        timer = nil
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutRing()
    }

    // MARK: - Step Building

    private func buildSteps() {
        steps = []
        let exercises: [(Int, WorkoutTemplate.Exercise)]
        if let single = singleExercise,
           let idx = workout.exercises.firstIndex(where: { $0.id == single.id }) {
            exercises = [(idx, single)]
        } else {
            exercises = Array(workout.exercises.enumerated())
        }

        for (index, exercise) in exercises {
            guard let duration = exercise.durationInSeconds else { continue }
            let setCount = exercise.parsedSetCount
            if setCount > 1 {
                for s in 1...setCount {
                    steps.append(TimerStep(
                        exerciseIndex: index,
                        exercise: exercise,
                        durationSeconds: duration,
                        setNumber: s,
                        totalSets: setCount
                    ))
                }
            } else {
                steps.append(TimerStep(
                    exerciseIndex: index,
                    exercise: exercise,
                    durationSeconds: duration,
                    setNumber: 0,
                    totalSets: 0
                ))
            }
        }
    }

    // MARK: - UI Setup

    private func setupUI() {
        let iconName = workout.iconName ?? "figure.run"
        workoutIconView.image = UIImage(systemName: iconName)
        workoutNameLabel.text = workout.name

        view.addSubview(workoutIconView)
        view.addSubview(workoutNameLabel)
        view.addSubview(closeButton)
        view.addSubview(stepCounterLabel)
        view.addSubview(exerciseNameLabel)
        view.addSubview(setLabel)
        view.addSubview(ringContainer)
        ringContainer.addSubview(timeLabel)

        let controlsStack = UIStackView(arrangedSubviews: [prevButton, playPauseButton, nextButton])
        controlsStack.axis = .horizontal
        controlsStack.spacing = 40
        controlsStack.alignment = .center
        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controlsStack)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            stepCounterLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            stepCounterLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            workoutIconView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 24),
            workoutIconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            workoutIconView.widthAnchor.constraint(equalToConstant: 32),
            workoutIconView.heightAnchor.constraint(equalToConstant: 32),

            workoutNameLabel.topAnchor.constraint(equalTo: workoutIconView.bottomAnchor, constant: 6),
            workoutNameLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            exerciseNameLabel.bottomAnchor.constraint(equalTo: setLabel.topAnchor, constant: -4),
            exerciseNameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            exerciseNameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            setLabel.bottomAnchor.constraint(equalTo: ringContainer.topAnchor, constant: -24),
            setLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            ringContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            ringContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 20),
            ringContainer.widthAnchor.constraint(equalToConstant: ringSize),
            ringContainer.heightAnchor.constraint(equalToConstant: ringSize),

            timeLabel.centerXAnchor.constraint(equalTo: ringContainer.centerXAnchor),
            timeLabel.centerYAnchor.constraint(equalTo: ringContainer.centerYAnchor),

            controlsStack.topAnchor.constraint(equalTo: ringContainer.bottomAnchor, constant: 48),
            controlsStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])

        // Create ring layers (positioned in layoutSubviews)
        trackLayer = CAShapeLayer()
        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.strokeColor = UIColor.tertiarySystemFill.cgColor
        trackLayer.lineWidth = ringLineWidth
        trackLayer.lineCap = .round
        ringContainer.layer.addSublayer(trackLayer)

        progressLayer = CAShapeLayer()
        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.strokeColor = UIColor.systemBlue.cgColor
        progressLayer.lineWidth = ringLineWidth
        progressLayer.lineCap = .round
        progressLayer.strokeEnd = 1.0
        ringContainer.layer.addSublayer(progressLayer)
    }

    private var lastRingBounds: CGRect = .zero

    private func layoutRing() {
        guard ringContainer.bounds != lastRingBounds else { return }
        lastRingBounds = ringContainer.bounds

        let center = CGPoint(x: ringContainer.bounds.midX, y: ringContainer.bounds.midY)
        let radius = (ringSize - ringLineWidth) / 2
        let path = UIBezierPath(
            arcCenter: center,
            radius: radius,
            startAngle: -.pi / 2,
            endAngle: 3 * .pi / 2,
            clockwise: true
        )
        trackLayer.path = path.cgPath
        progressLayer.path = path.cgPath
    }

    // MARK: - Actions

    private func setupActions() {
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        prevButton.addTarget(self, action: #selector(prevTapped), for: .touchUpInside)
    }

    @objc private func closeTapped() {
        if isRunning || elapsedTime > 0 {
            HapticManager.shared.warning()
            let alert = UIAlertController(
                title: "End Workout?",
                message: "Completed exercises will be saved. Remaining exercises will not be marked complete.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "End", style: .destructive) { [weak self] _ in
                guard let self else { return }
                self.stopTimer()
                self.delegate?.workoutTimerDidCancel(self)
                self.dismiss(animated: true)
            })
            present(alert, animated: true)
        } else {
            delegate?.workoutTimerDidCancel(self)
            dismiss(animated: true)
        }
    }

    @objc private func playPauseTapped() {
        HapticManager.shared.medium()
        if isRunning {
            pauseTimer()
        } else {
            startTimer()
        }
    }

    @objc private func nextTapped() {
        guard currentStepIndex < steps.count - 1 else { return }
        HapticManager.shared.selection()
        let skippedStep = steps[currentStepIndex]
        stopTimer()
        currentStepIndex += 1
        elapsedTime = 0

        // If the next step is a different exercise (or we skipped the last set), mark the skipped exercise complete
        let nextStep = steps[currentStepIndex]
        if nextStep.exerciseIndex != skippedStep.exerciseIndex {
            markExerciseCompleted(at: skippedStep.exerciseIndex)
        }

        updateDisplay()
    }

    @objc private func prevTapped() {
        HapticManager.shared.selection()
        stopTimer()
        if elapsedTime > 1 {
            // If more than 1 second in, restart current step
            elapsedTime = 0
        } else if currentStepIndex > 0 {
            currentStepIndex -= 1
            elapsedTime = 0
        }
        updateDisplay()
    }

    // MARK: - Timer

    private func startTimer() {
        guard !isRunning, currentStepIndex < steps.count else { return }
        isRunning = true
        updatePlayPauseIcon()

        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func pauseTimer() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        updatePlayPauseIcon()
    }

    private func stopTimer() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        updatePlayPauseIcon()
    }

    private func tick() {
        guard currentStepIndex < steps.count else {
            stopTimer()
            return
        }
        let step = steps[currentStepIndex]
        elapsedTime += 0.05

        if elapsedTime >= step.durationSeconds {
            // Step complete
            if currentStepIndex < steps.count - 1 {
                HapticManager.shared.timerStepComplete()
            } else {
                HapticManager.shared.timerComplete()
            }

            if currentStepIndex < steps.count - 1 {
                let nextIndex = currentStepIndex + 1
                let nextStep = steps[nextIndex]

                // If moving to a different exercise, mark the current one complete
                if nextStep.exerciseIndex != step.exerciseIndex {
                    markExerciseCompleted(at: step.exerciseIndex)
                }

                currentStepIndex = nextIndex
                elapsedTime = 0
                updateDisplay()
            } else {
                // Last step — mark final exercise complete and finish
                markExerciseCompleted(at: step.exerciseIndex)
                stopTimer()
                completeWorkout()
            }
        } else {
            updateTimeDisplay()
            updateRingProgress()
        }
    }

    // MARK: - Display

    private func updateDisplay() {
        guard currentStepIndex < steps.count else { return }
        let step = steps[currentStepIndex]

        // Exercise name
        exerciseNameLabel.text = step.exercise.name

        // Set label
        if step.totalSets > 0 {
            setLabel.text = "Set \(step.setNumber) of \(step.totalSets)"
            setLabel.isHidden = false
        } else {
            setLabel.isHidden = true
        }

        // Step counter — count unique exercise indices
        let uniqueExerciseIndices = Set(steps.map(\.exerciseIndex)).sorted()
        let currentExercisePosition = (uniqueExerciseIndices.firstIndex(of: step.exerciseIndex) ?? 0) + 1
        stepCounterLabel.text = "Exercise \(currentExercisePosition) of \(uniqueExerciseIndices.count)"

        // Navigation button states
        prevButton.isEnabled = currentStepIndex > 0 || elapsedTime > 1
        prevButton.tintColor = prevButton.isEnabled ? .label : .tertiaryLabel
        nextButton.isEnabled = currentStepIndex < steps.count - 1
        nextButton.tintColor = nextButton.isEnabled ? .label : .tertiaryLabel

        updateTimeDisplay()
        updateRingProgress()
        updatePlayPauseIcon()
    }

    private func updateTimeDisplay() {
        guard currentStepIndex < steps.count else { return }
        let step = steps[currentStepIndex]
        let remaining = max(0, step.durationSeconds - elapsedTime)
        timeLabel.text = formatTime(remaining)
    }

    private func updateRingProgress() {
        guard currentStepIndex < steps.count else { return }
        let step = steps[currentStepIndex]
        let progress = min(1.0, elapsedTime / step.durationSeconds)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.strokeEnd = CGFloat(1.0 - progress)
        CATransaction.commit()
    }

    private func updatePlayPauseIcon() {
        let config = UIImage.SymbolConfiguration(pointSize: 44, weight: .medium)
        let imageName = isRunning ? "pause.circle.fill" : "play.circle.fill"
        playPauseButton.setImage(UIImage(systemName: imageName, withConfiguration: config), for: .normal)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(ceil(seconds))
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    // MARK: - Completion

    private func markExerciseCompleted(at exerciseIndex: Int) {
        guard !completedExerciseIndices.contains(exerciseIndex) else { return }
        completedExerciseIndices.insert(exerciseIndex)
        let exercise = workout.exercises[exerciseIndex]
        delegate?.workoutTimer(self, didCompleteExercise: exercise, in: workout)
    }

    private func completeWorkout() {
        delegate?.workoutTimerDidComplete(self, workout: workout)
        dismiss(animated: true)
    }
}
