# Quantum Observatory: model and scientific basis

This is a **classical quantum-inspired model**, implemented with deterministic integer arithmetic. There is no quantum hardware, quantum entropy, physical measurement, prediction oracle, or claim of quantum computational advantage. An observation is a user's chosen label, not a sample drawn from a probability distribution. The token's price, supply distribution, and balances never enter the transition calculation.

## Exact implemented rule

Let `S = 1,000,000`. The stored vector `P` has eight nonnegative integer entries with `sum(P) = S`; initially every entry is `125,000`. The displayed probability of state `i` is `P_i / S`, or `P_i / 10,000` percent. Let `c_i` be the current epoch's observation counts and `N = sum(c)`, with `0 <= N <= 1,024`.

Define `A(w)` to apportion `S` integer units among eight nonnegative weights. For `W = sum(w) > 0`:

```text
q_i = floor(S * w_i / W)
r_i = (S * w_i) mod W
L   = S - sum(q)
```

Add one unit to each of the `L` largest remainders, breaking ties toward the lower index. `0 <= L <= 7`, so this requires at most seven selections. Each output differs from its exact real allocation by less than one integer unit, and the sum is exactly `S`. Ties produce a documented small index bias; no entropy or caller data resolves them.

The complete transition in `src/QuantumModel.sol` is:

```text
a_j = floor(sqrt(P_j * S))
K_ij = (-1)^popcount(i AND j)          for i,j in {0,...,7}
b_i = sum_j K_ij * a_j
C = A([b_0^2, ..., b_7^2])
B = A([3*C_i + S/8]_i)

P_next = B                                         if N = 0
P_next = A([3*B_i*N + c_i*S]_i)                     if N > 0
```

The Solidity code evaluates `K` using three butterfly stages. In real arithmetic, `K / sqrt(8) = H tensor H tensor H`, where `H = [[1,1],[1,-1]] / sqrt(2)`. The omitted common factor cancels when `A` normalizes squared amplitudes. Negative intermediate amplitudes cancel positive contributions before squaring, providing the interference-like behavior. Squaring amplitudes is inspired by the Born probability rule; applying signed transforms follows the Hadamard examples discussed in sources 1–4 below.

`B/S` approximates `3/4 * (C/S) + 1/4 * uniform`. With observations, `P_next/S` approximates `3/4 * (B/S) + 1/4 * (c/N)`. Normalization happens at **each** stage; combining the rational formulas and rounding only at the end would yield a different model.

The uniform term admits a depolarizing-channel analogy: for a normalized prepared state `psi`, one could form `rho' = (3/4) U|psi><psi|U† + (1/4) I/8`, whose diagonal has that mixture. This is our design interpretation, not a fitted environmental model or a result asserted by the cited papers. It is specifically not the same as pure dephasing, which can suppress off-diagonal terms without making the diagonal uniform (sources 6–8).

The feedback weight is fixed at 25% for every nonempty epoch; one observation receives the same aggregate feedback weight as 1,024 unanimous observations. The count affects empirical frequencies, not confidence. This is a product rule, not a quantum measurement postulate or a statistically calibrated estimator. Empty epochs still perform the interference and uniform-mixing steps.

## Worked values and bounds

From the initial uniform vector, all reconstructed amplitudes are equal. Therefore the transform cancels exactly in states 1–7 and adds constructively in state 0. With no observations:

```text
[781250, 31250, 31250, 31250, 31250, 31250, 31250, 31250]
```

With one observation of state 7, the first advancement instead gives:

```text
[585938, 23438, 23438, 23438, 23437, 23437, 23437, 273437]
```

The unequal final units are largest-remainder tie breaking. Any basis vector `[S,0,...,0]` and its permutations becomes uniform after the transform in an empty epoch. These examples are included among the 32 committed reference vectors.

For a valid input, each `a_i <= 10^6`, and floor square roots introduce less than `10^-6` absolute error in `a_i/S` relative to `sqrt(P_i/S)`. The reconstruction has positive norm. Orthogonality gives `sum(b_i^2) = 8*sum(a_i^2) <= 8*10^12`, so the normalization denominator cannot vanish and its scaled numerators fit well inside `uint256`. Observed mixing has total weight `4*N*S <= 4.096*10^9`. The post-transition vector remains nonnegative, sums to `S`, and each component lies between `23,437` and `835,938`; an empty epoch has the stronger lower bound `31,250`.

Those arithmetic bounds are properties of this implementation. They do not quantify long-run error against a physical system. `tools/model_reference.py` is an independent numerical specification using an explicit signed matrix, Python's integer square root, and sorting for apportionment. The Solidity implementation instead uses butterflies, Newton iteration, and bounded remainder selection. Thirty-two differential vectors, repeated-transition fuzzing, and stateful engine invariants check their agreement and conservation.

## Approximations and unknowns

- Only probabilities persist. Every epoch reconstructs **nonnegative real** amplitudes with zero relative phases. Prior signs, complex phases, entanglement, and off-diagonal density-matrix information are discarded. Repreparing a pure amplitude vector from these probabilities adds an assumption; it is not equivalent to retaining the diagonal mixed state.
- Consequently the whole multi-epoch map is nonlinear in `P`, not a fixed unitary or a faithful simulation of an open quantum system. Eight labels are a three-bit basis convention, not spatial positions, measured energies, or physical qubits. There is no graph shift/coin register as in the cited walks.
- The values 25%, 25%, eight states, and one hour are uncalibrated design choices. Papers about weak decoherence do not establish that 25% is optimal here. User-selected feedback is classical input, not an experimental measurement ensemble.
- Floor square roots and three apportionment stages quantize the model. Each normalization contributes less than one unit per component relative to that stage's rational weights. There is no proven cumulative physical-error bound, convergence theorem, unique stationary distribution, or claim that state 0 is unbiased. Zero-phase preparation visibly privileges state 0 on the initial transition.
- Submission order does not affect a fixed accepted histogram. Censorship, the capacity cutoff, token recycling, and Sybil addresses can affect that histogram. More QOBS does not increase one address's per-epoch weight; balances are checked only at submission.
- Block time controls eligibility, not the numerical transition. Delays do not accumulate physical evolution. One advancement processes one expired epoch and begins another complete window. No lottery or valuable randomness should rely on these public deterministic outputs.

## Ten publications reviewed

The linked primary-source full texts were accessed during implementation on **2026-10-07**. The reading notes identify the relevant mathematical or interpretive material and its specific use or limit here. These sources motivate analogies; none validates this contract or its constants. Links are to the papers themselves, not search results.

1. **Wojciech H. Zurek, _Probabilities from Entanglement, Born's Rule from Envariance_** (2005; arXiv quant-ph/0405161). Section II develops squared-amplitude probabilities from envariance; its discussion of phases emphasizes that discarding them generally loses information. We use the squared-amplitude rule and explicitly disclose the zero-phase reconstruction. We do not implement entanglement or claim to reproduce the derivation. [Full text](https://arxiv.org/pdf/quant-ph/0405161).

2. **Julia Kempe, _Quantum random walks — an introductory overview_** (2003; arXiv quant-ph/0303081). The discrete-walk discussion, especially equation (13), gives the signed Hadamard coin and shows how cancellations alter probabilities. This motivates a simple signed transform, but our eight-state tensor transform omits the walk's conditional position shift. [Full text](https://arxiv.org/pdf/quant-ph/0303081).

3. **Ashwin Nayak and Ashvin Vishwanath, _Quantum Walk on the Line_** (2000; arXiv quant-ph/0010117). Section 2.1 defines the Hadamard transformation on chirality and its coupled position update; the Fourier analysis studies the resulting amplitudes. This supplies a concrete interference example and highlights why probability storage alone cannot retain a quantum walk's state. [Full text](https://arxiv.org/pdf/quant-ph/0010117).

4. **Peter L. Knight, Eugenio Roldán, and J. E. Sipe, _Quantum walk on the line as an interference phenomenon_** (2003; arXiv quant-ph/0304201). The optical construction and difference equations explain how a walk's interference pattern can have a classical implementation. That distinction supports describing this software as quantum-inspired without attributing nonclassical hardware or computational advantage to it. [Full text](https://arxiv.org/pdf/quant-ph/0304201).

5. **Dorit Aharonov, Andris Ambainis, Julia Kempe, and Umesh Vazirani, _Quantum Walks on Graphs_** (2001; arXiv quant-ph/0012090, revised 2002). The introduction and mixing definitions distinguish unitary evolution from Markov-chain convergence and use time-averaged distributions. We therefore make no convergence claim from the mere use of a Hadamard transform; our feedback/reset map is a different process. [Full text](https://arxiv.org/pdf/quant-ph/0012090).

6. **Wojciech H. Zurek, _Decoherence, einselection, and the quantum origins of the classical_** (2003; arXiv quant-ph/0105127). The density-matrix discussion and position-space damping equations distinguish coherence loss from population change. This constrains our terminology: uniform mixing is a depolarizing analogy, while real environment-induced decoherence involves correlations and preferred states absent from the engine. [Full text](https://arxiv.org/pdf/quant-ph/0105127).

7. **Maximilian Schlosshauer, _Decoherence, the measurement problem, and interpretations of quantum mechanics_** (arXiv 2003, revised 2005; quant-ph/0312059). Section III's reduced-density-matrix example, equations (3.14)–(3.17), exposes the interference coefficient and its environmental damping. It justifies documenting that our eight probabilities omit coherences and that user observations do not resolve the physical measurement problem. [Full text](https://arxiv.org/pdf/quant-ph/0312059).

8. **Todd A. Brun, Hilary A. Carteret, and Andris Ambainis, _The quantum to classical transition for random walks_** (2003; arXiv quant-ph/0208195). The coin-noise model, including the dephasing operators in equation (25), contrasts decoherence with merely increasing coin dimension. We retain a distinct mixing stage and do not claim that an enlarged classical state vector alone constitutes decoherence. Their asymptotic variance results do not apply to our reset map. [Full text](https://arxiv.org/pdf/quant-ph/0208195).

9. **Viv Kendon and Ben Tregenna, _Decoherence can be useful in quantum walks_** (2003; arXiv quant-ph/0209005). Section III introduces density-matrix evolution with intermittent decoherence and studies effects on spreading and uniformity. It motivates considering an explicit noise contribution while leaving its rate a documented design choice. It does not establish an optimal rate for this application. [Full text](https://arxiv.org/pdf/quant-ph/0209005).

10. **Viv Kendon, _Decoherence in quantum walks — a review_** (2007; arXiv quant-ph/0606016). The mixed-state formalism and equation (49) combine coherent evolution with projected evolution. They support separating an interference calculation from a nonunitary contribution and specifying precisely which channel analogy is used. Our uniform mixing and histogram feedback are not the review's projection superoperator. [Full text](https://arxiv.org/pdf/quant-ph/0606016).

## Website handoff

The frontend stage must render this complete document, including equations, approximations, unknowns, and all ten links, on the published IPFS website. Bundle its content into the site's build so reading it does not depend on GitHub or a live research service; the external links remain references. Pair probability percentages with a visible “classical deterministic model” description. Display no claims of physical observation, quantum randomness, price prediction, or rewards.
